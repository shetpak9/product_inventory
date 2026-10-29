import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_thumb.dart';
import 'package:product_inventory/shared/option_summary.dart';

enum _OrderFilter { active, completed, cancelled }

class SellerOrdersTab extends StatefulWidget {
  const SellerOrdersTab({
    super.key,
    required this.orders,
    required this.loading,
    this.error,
  });

  final List<Order>? orders;
  final bool loading;
  final Object? error;

  @override
  State<SellerOrdersTab> createState() => _SellerOrdersTabState();
}

class _SellerOrdersTabState extends State<SellerOrdersTab> {
  _OrderFilter _filter = _OrderFilter.active;

  List<Order> _filteredOrders(List<Order> orders) {
    return orders.where((Order order) {
      return switch (_filter) {
        _OrderFilter.active =>
          order.status != OrderStatus.delivered &&
              order.status != OrderStatus.cancelled,
        _OrderFilter.completed => order.status == OrderStatus.delivered,
        _OrderFilter.cancelled => order.status == OrderStatus.cancelled,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<Order> orders = widget.orders ?? <Order>[];
    final List<Order> filteredOrders = _filteredOrders(orders);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              for (final (_OrderFilter, String) option
                  in <(_OrderFilter, String)>[
                    (_OrderFilter.active, 'Active'),
                    (_OrderFilter.completed, 'Completed'),
                    (_OrderFilter.cancelled, 'Cancelled'),
                  ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: _filter == option.$1,
                  onSelected: (_) => setState(() => _filter = option.$1),
                ),
            ],
          ),
        ),
        Expanded(
          child: widget.error != null
              ? Center(child: Text('Unable to load orders: ${widget.error}'))
              : widget.loading
              ? const Center(child: CircularProgressIndicator())
              : filteredOrders.isEmpty
              ? Center(
                  child: Text(switch (_filter) {
                    _OrderFilter.active => 'No active orders.',
                    _OrderFilter.completed => 'No completed orders yet.',
                    _OrderFilter.cancelled => 'No cancelled orders.',
                  }),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: filteredOrders.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int index) {
                    final Order order = filteredOrders[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${order.fulfillment.type.label} · ${order.fulfillment.date}'
                          '${order.fulfillment.timeSlotLabel.isEmpty ? '' : ' · ${order.fulfillment.timeSlotLabel}'}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(order.customerName),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: <Widget>[
                                  Text('${order.items.length} item(s)'),
                                  _StatusChip(status: order.status),
                                ],
                              ),
                            ],
                          ),
                        ),
                        trailing: Text(formatPeso(order.total)),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SellerOrderDetailScreen(orderId: order.id),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class SellerOrderDetailScreen extends StatefulWidget {
  const SellerOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<SellerOrderDetailScreen> createState() =>
      _SellerOrderDetailScreenState();
}

class _SellerOrderDetailScreenState extends State<SellerOrderDetailScreen> {
  final DatabaseService _database = DatabaseService();
  late final Stream<Order?> _orderStream = _database.orderStream(
    widget.orderId,
  );
  bool _updating = false;

  Future<void> _changeStatus(Order order, OrderStatus status) async {
    if (status == OrderStatus.cancelled) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Cancel order?'),
          content: const Text(
            'The customer will see that this order was cancelled.',
          ),
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
    }

    setState(() => _updating = true);
    try {
      await _database.updateOrderStatus(order.id, status);
    } catch (error) {
      debugPrint('Order status update failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update this order: $error')),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
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
    final List<OrderStatus> availableStatuses = nextStatuses(
      order.status,
      fulfillmentType: order.fulfillment.type,
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          order.customerName,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _StatusChip(status: order.status),
        const SizedBox(height: 20),
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
            'Note from customer',
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
        if (availableStatuses.isNotEmpty) ...<Widget>[
          const SizedBox(height: 20),
          for (final OrderStatus status in availableStatuses)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ElevatedButton(
                onPressed: _updating
                    ? null
                    : () => _changeStatus(order, status),
                style: status == OrderStatus.cancelled
                    ? ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      )
                    : null,
                child: _updating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Mark ${status.label.toLowerCase()}'),
              ),
            ),
        ],
      ],
    );
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
