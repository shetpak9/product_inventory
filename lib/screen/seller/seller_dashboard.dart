import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/seller/seller_orders.dart';
import 'package:product_inventory/shared/app_theme.dart';

class SellerDashboardTab extends StatefulWidget {
  const SellerDashboardTab({
    super.key,
    required this.orders,
    this.products = const <Product>[],
    required this.loading,
    this.error,
  });

  final List<Order>? orders;
  final List<Product>? products;
  final bool loading;
  final Object? error;

  @override
  State<SellerDashboardTab> createState() => _SellerDashboardTabState();
}

class _SellerDashboardTabState extends State<SellerDashboardTab> {
  DateTimeRange? _dateRange;

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return Center(
        child: Text('Unable to load dashboard data: ${widget.error}'),
      );
    }
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Order> allOrders = widget.orders ?? <Order>[];
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime tomorrow = DateTime(today.year, today.month, today.day + 1);
    final DateTimeRange selectedRange =
        _dateRange ??
        DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 29),
          end: today,
        );
    final DateTime rangeEnd = DateTime(
      selectedRange.end.year,
      selectedRange.end.month,
      selectedRange.end.day + 1,
    );
    final List<Order> rangeOrders = allOrders
        .where((Order order) => _inRange(order, selectedRange.start, rangeEnd))
        .toList();
    final List<Order> confirmedOrders = rangeOrders
        .where(_isConfirmedSale)
        .toList();
    final List<Order> todaysOrders = allOrders
        .where((Order order) => _inRange(order, today, tomorrow))
        .toList();
    final List<_ProductQuantity> topProducts = _topProducts(rangeOrders);
    final List<Product> lowStockProducts =
        (widget.products ?? <Product>[])
            .where(
              (Product product) =>
                  product.stockQuantity != null && product.stockQuantity! <= 5,
            )
            .toList()
          ..sort(
            (Product a, Product b) =>
                (a.stockQuantity ?? 0).compareTo(b.stockQuantity ?? 0),
          );
    final int pendingOrders = rangeOrders
        .where((Order order) => order.status == OrderStatus.pending)
        .length;
    final int completedOrders = rangeOrders
        .where((Order order) => order.status == OrderStatus.delivered)
        .length;
    final double totalSales = confirmedOrders.fold<double>(
      0,
      (double total, Order order) => total + _saleAmount(order),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Business overview',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Choose date range',
              icon: const Icon(Icons.date_range),
              onPressed: () async {
                final DateTimeRange? picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: selectedRange,
                );
                if (picked != null && mounted) {
                  setState(() => _dateRange = picked);
                }
              },
            ),
          ],
        ),
        Text(
          '${_formatDate(selectedRange.start)} - ${_formatDate(selectedRange.end)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _MetricCard(
                  width: cardWidth,
                  label: 'Total sales',
                  value: formatPeso(totalSales),
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Total orders',
                  value:
                      '${rangeOrders.where((Order order) => order.status != OrderStatus.cancelled).length}',
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Pending',
                  value: '$pendingOrders',
                ),
                _MetricCard(
                  width: cardWidth,
                  label: 'Completed',
                  value: '$completedOrders',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          "Today's orders",
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${todaysOrders.length} ${todaysOrders.length == 1 ? 'order' : 'orders'}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (todaysOrders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('No orders placed today.'),
                  )
                else ...<Widget>[
                  const SizedBox(height: 8),
                  for (final Order order in todaysOrders.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(order.customerName),
                      subtitle: Text(order.status.label),
                      trailing: Text(formatPeso(order.total)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              SellerOrderDetailScreen(orderId: order.id),
                        ),
                      ),
                    ),
                  if (todaysOrders.length > 5)
                    Text('And ${todaysOrders.length - 5} more'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Delivered revenue',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _RevenueCard(
                  width: cardWidth,
                  label: 'Today',
                  amount: _salesInRange(allOrders, today, tomorrow),
                ),
                _RevenueCard(
                  width: cardWidth,
                  label: 'Last 7 days',
                  amount: _salesInRange(
                    allOrders,
                    DateTime(today.year, today.month, today.day - 6),
                    tomorrow,
                  ),
                ),
                _RevenueCard(
                  width: cardWidth,
                  label: 'Last 30 days',
                  amount: _salesInRange(
                    allOrders,
                    DateTime(today.year, today.month, today.day - 29),
                    tomorrow,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Top products by quantity',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          child: topProducts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No product sales to rank yet.'),
                )
              : Column(
                  children: <Widget>[
                    for (int index = 0; index < topProducts.length; index++)
                      ListTile(
                        leading: CircleAvatar(child: Text('${index + 1}')),
                        title: Text(topProducts[index].name),
                        trailing: Text('${topProducts[index].quantity} sold'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 20),
        Text(
          'Low-stock products',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          child: lowStockProducts.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No products at or below 5 items.'),
                )
              : Column(
                  children: lowStockProducts.take(8).map((Product product) {
                    return ListTile(
                      title: Text(product.name),
                      trailing: Text(
                        product.stockQuantity == 0
                            ? 'Out of stock'
                            : '${product.stockQuantity} left',
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }

  static DateTime? _localDate(int? timestamp) {
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  }

  static bool _isConfirmedSale(Order order) {
    return order.status != OrderStatus.cancelled &&
        (order.paymentStatus == 'paid' ||
            (order.paymentMethod == 'cash' &&
                order.status == OrderStatus.delivered));
  }

  static double _saleAmount(Order order) {
    return order.discountAmount > 0
        ? order.total - order.discountAmount
        : order.total;
  }

  static bool _inRange(Order order, DateTime start, DateTime end) {
    final DateTime? createdAt = _localDate(order.createdAt);
    return createdAt != null &&
        !createdAt.isBefore(start) &&
        createdAt.isBefore(end);
  }

  static double _salesInRange(
    List<Order> orders,
    DateTime start,
    DateTime end,
  ) {
    return orders.fold<double>(0, (double total, Order order) {
      if (!_isConfirmedSale(order) || !_inRange(order, start, end)) {
        return total;
      }
      return total + _saleAmount(order);
    });
  }

  static List<_ProductQuantity> _topProducts(List<Order> orders) {
    final Map<String, _ProductQuantity> quantities =
        <String, _ProductQuantity>{};
    for (final Order order in orders) {
      if (order.status == OrderStatus.cancelled) continue;
      for (final OrderItem item in order.items) {
        if (item.productId.isEmpty) continue;
        final _ProductQuantity? existing = quantities[item.productId];
        if (existing == null) {
          quantities[item.productId] = _ProductQuantity(
            name: item.productName,
            quantity: item.quantity,
          );
        } else {
          existing.quantity += item.quantity;
        }
      }
    }

    final List<_ProductQuantity> result = quantities.values.toList()
      ..sort((_ProductQuantity a, _ProductQuantity b) {
        final int quantityOrder = b.quantity.compareTo(a.quantity);
        return quantityOrder != 0
            ? quantityOrder
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return result.take(5).toList();
  }

  static String _formatDate(DateTime date) =>
      '${date.month}/${date.day}/${date.year}';
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
  });

  final double width;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.width,
    required this.label,
    required this.amount,
  });

  final double width;
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                formatPeso(amount),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductQuantity {
  _ProductQuantity({required this.name, required this.quantity});

  final String name;
  int quantity;
}
