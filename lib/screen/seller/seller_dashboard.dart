import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/screen/seller/seller_orders.dart';
import 'package:product_inventory/shared/app_theme.dart';

class SellerDashboardTab extends StatelessWidget {
  const SellerDashboardTab({
    super.key,
    required this.orders,
    required this.loading,
    this.error,
  });

  final List<Order>? orders;
  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Center(child: Text('Unable to load dashboard data: $error'));
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Order> allOrders = orders ?? <Order>[];
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime tomorrow = DateTime(today.year, today.month, today.day + 1);
    final List<Order> todaysOrders = allOrders.where((Order order) {
      final DateTime? createdAt = _localDate(order.createdAt);
      return createdAt != null &&
          !createdAt.isBefore(today) &&
          createdAt.isBefore(tomorrow);
    }).toList();
    final List<_ProductQuantity> topProducts = _topProducts(allOrders);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: <Widget>[
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
                  amount: _deliveredRevenue(allOrders, today, tomorrow),
                ),
                _RevenueCard(
                  width: cardWidth,
                  label: 'Last 7 days',
                  amount: _deliveredRevenue(
                    allOrders,
                    DateTime(today.year, today.month, today.day - 6),
                    tomorrow,
                  ),
                ),
                _RevenueCard(
                  width: cardWidth,
                  label: 'Last 30 days',
                  amount: _deliveredRevenue(
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
      ],
    );
  }

  static DateTime? _localDate(int? timestamp) {
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
  }

  static double _deliveredRevenue(
    List<Order> orders,
    DateTime start,
    DateTime end,
  ) {
    return orders.fold<double>(0, (double total, Order order) {
      if (order.status != OrderStatus.delivered) return total;
      final DateTime? deliveredAt = _localDate(
        order.updatedAt ?? order.createdAt,
      );
      if (deliveredAt == null ||
          deliveredAt.isBefore(start) ||
          !deliveredAt.isBefore(end)) {
        return total;
      }
      return total + order.total;
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
