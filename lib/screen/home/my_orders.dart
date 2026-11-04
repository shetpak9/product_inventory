import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_thumb.dart';
import 'package:product_inventory/shared/option_summary.dart';

class MyOrdersScreen extends StatefulWidget {
  const MyOrdersScreen({super.key});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final DatabaseService _database = DatabaseService();
  late final Stream<List<Order>> _ordersStream;

  @override
  void initState() {
    super.initState();
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    _ordersStream = uid == null
        ? Stream<List<Order>>.error(
            StateError('A signed-in customer is required to view orders.'),
          )
        : _database.customerOrdersStream(uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My orders')),
      body: StreamBuilder<List<Order>>(
        stream: _ordersStream,
        builder: (BuildContext context, AsyncSnapshot<List<Order>> snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load your orders: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Order> orders = snapshot.data!;
          if (orders.isEmpty) {
            return const Center(child: Text('You have not placed any orders.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (BuildContext context, int index) {
              final Order order = orders[index];
              return Card(
                child: ListTile(
                  title: Text(
                    order.storeName.isEmpty ? 'Store order' : order.storeName,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('${order.items.length} item(s)'),
                        const SizedBox(height: 8),
                        _StatusChip(status: order.status),
                      ],
                    ),
                  ),
                  trailing: Text(formatPeso(order.total)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          CustomerOrderDetailScreen(orderId: order.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class CustomerOrderDetailScreen extends StatefulWidget {
  const CustomerOrderDetailScreen({
    super.key,
    required this.orderId,
    this.initialMessage,
  });

  final String orderId;
  final String? initialMessage;

  @override
  State<CustomerOrderDetailScreen> createState() =>
      _CustomerOrderDetailScreenState();
}

class _CustomerOrderDetailScreenState extends State<CustomerOrderDetailScreen> {
  final DatabaseService _database = DatabaseService();
  late final Stream<Order?> _orderStream = _database.orderStream(
    widget.orderId,
  );
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    final String? message = widget.initialMessage;
    if (message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      });
    }
  }

  Future<void> _cancel(Order order) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Cancel order?'),
        content: const Text('This order can no longer be prepared.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep order'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _cancelling = true);
    try {
      await _database.updateOrderStatus(order.id, OrderStatus.cancelled);
    } catch (error) {
      debugPrint('Order cancellation failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel this order: $error')),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order details')),
      body: StreamBuilder<Order?>(
        stream: _orderStream,
        builder: (BuildContext context, AsyncSnapshot<Order?> snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Unable to load this order: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final Order? order = snapshot.data;
          if (order == null) {
            return const Center(
              child: Text('This order is no longer available.'),
            );
          }
          return _buildOrder(context, order);
        },
      ),
    );
  }

  Widget _buildOrder(BuildContext context, Order order) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          order.storeName,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _StatusChip(status: order.status),
        const SizedBox(height: 6),
        Text(
          'Payment: ${_paymentLabel(order)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 20),
        Text('Order progress', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final OrderStatus status in <OrderStatus>[
          OrderStatus.pending,
          OrderStatus.accepted,
          OrderStatus.baking,
          OrderStatus.ready,
          if (order.fulfillment.type == FulfillmentType.delivery)
            OrderStatus.outForDelivery,
          OrderStatus.delivered,
        ])
          _TimelineRow(
            status: status,
            reached: order.status == OrderStatus.cancelled
                ? false
                : order.status.index >= status.index,
            current: order.status == status,
          ),
        if (order.status == OrderStatus.cancelled)
          const _TimelineRow(
            status: OrderStatus.cancelled,
            reached: true,
            current: true,
          ),
        const SizedBox(height: 16),
        const Text('Items', style: TextStyle(fontWeight: FontWeight.w600)),
        for (final OrderItem item in order.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ProductThumb(url: item.imageUrl),
            title: Text(item.productName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${formatPeso(item.price + item.priceAdjustment)} × ${item.quantity}',
                ),
                OptionSummary(options: item.selectedOptions),
              ],
            ),
            trailing: Text(formatPeso(item.lineTotal)),
          ),
        if (order.note != null && order.note!.isNotEmpty) ...<Widget>[
          const Divider(),
          const Text(
            'Note to seller',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(order.note!),
        ],
        const Divider(height: 28),
        Text(
          '${order.fulfillment.type.label} · ${order.fulfillment.date}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (order.fulfillment.timeSlotLabel.isNotEmpty)
          Text('Preferred time: ${order.fulfillment.timeSlotLabel}'),
        if (order.fulfillment.type == FulfillmentType.delivery) ...<Widget>[
          const SizedBox(height: 4),
          if (order.fulfillment.addressLabel.isNotEmpty)
            Text('Address label: ${order.fulfillment.addressLabel}'),
          if (order.fulfillment.addressRecipient.isNotEmpty)
            Text('Recipient: ${order.fulfillment.addressRecipient}'),
          if (order.fulfillment.addressPhone.isNotEmpty)
            Text('Contact: ${order.fulfillment.addressPhone}'),
          Text('Delivery address: ${order.fulfillment.addressOneLine}'),
          if (order.fulfillment.addressNotes.isNotEmpty)
            Text('Delivery notes: ${order.fulfillment.addressNotes}'),
          const SizedBox(height: 4),
          Text('Delivery fee: ${formatPeso(order.deliveryFee)}'),
        ],
        const Divider(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              formatPeso(order.total),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        if (order.status == OrderStatus.pending) ...<Widget>[
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _cancelling ? null : () => _cancel(order),
            child: _cancelling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel order'),
          ),
        ],
      ],
    );
  }

  String _paymentLabel(Order order) {
    if (order.paymentMethod != 'paymongo') return 'Cash on delivery';
    return switch (order.paymentStatus) {
      'paid' => 'Paid',
      'failed' => 'Payment failed',
      'pending' => 'Payment pending confirmation',
      _ => 'Payment not started',
    };
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(status.label),
      backgroundColor: status.color.withValues(alpha: 0.15),
      side: BorderSide(color: status.color.withValues(alpha: 0.6)),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.status,
    required this.reached,
    required this.current,
  });

  final OrderStatus status;
  final bool reached;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final Color color = reached ? status.color : Colors.grey;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        reached ? Icons.check_circle : Icons.radio_button_unchecked,
        color: color,
      ),
      title: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: current ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
  }
}
