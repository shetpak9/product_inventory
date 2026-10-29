import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/screen/seller/seller_dashboard.dart';

void main() {
  testWidgets('summarizes order periods and ranks non-cancelled quantities', (
    WidgetTester tester,
  ) async {
    final DateTime today = DateTime.now();
    final DateTime sixDaysAgo = DateTime(
      today.year,
      today.month,
      today.day - 6,
      12,
    );
    final DateTime tenDaysAgo = DateTime(
      today.year,
      today.month,
      today.day - 10,
      12,
    );
    final List<Order> orders = <Order>[
      _order(
        id: 'today',
        status: OrderStatus.delivered,
        createdAt: today,
        updatedAt: today,
        total: 100,
        items: const <OrderItem>[
          OrderItem(
            productId: 'croissant',
            productName: 'Croissant',
            price: 10,
            quantity: 2,
          ),
        ],
      ),
      _order(
        id: 'six-days',
        status: OrderStatus.delivered,
        createdAt: sixDaysAgo,
        updatedAt: sixDaysAgo,
        total: 200,
        items: const <OrderItem>[
          OrderItem(
            productId: 'croissant',
            productName: 'Croissant',
            price: 10,
            quantity: 3,
          ),
          OrderItem(
            productId: 'baguette',
            productName: 'Baguette',
            price: 10,
            quantity: 1,
          ),
        ],
      ),
      _order(
        id: 'ten-days',
        status: OrderStatus.delivered,
        createdAt: tenDaysAgo,
        updatedAt: tenDaysAgo,
        total: 300,
        items: const <OrderItem>[
          OrderItem(
            productId: 'baguette',
            productName: 'Baguette',
            price: 10,
            quantity: 2,
          ),
        ],
      ),
      _order(
        id: 'cancelled',
        status: OrderStatus.cancelled,
        createdAt: today,
        updatedAt: today,
        total: 500,
        items: const <OrderItem>[
          OrderItem(
            productId: 'croissant',
            productName: 'Croissant',
            price: 10,
            quantity: 99,
          ),
        ],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SellerDashboardTab(orders: orders, loading: false),
        ),
      ),
    );

    expect(find.text('2 orders'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Top products by quantity'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('5 sold'), findsOneWidget);
    expect(find.text('3 sold'), findsOneWidget);
    expect(find.text('99 sold'), findsNothing);
    expect(find.text('₱100.00'), findsNWidgets(2));
    expect(find.text('₱300.00'), findsOneWidget);
    expect(find.text('₱600.00'), findsOneWidget);
  });
}

Order _order({
  required String id,
  required OrderStatus status,
  required DateTime createdAt,
  required DateTime updatedAt,
  required double total,
  required List<OrderItem> items,
}) {
  return Order(
    id: id,
    customerId: 'customer',
    customerName: 'Customer',
    sellerId: 'seller',
    storeName: 'Bakery',
    items: items,
    subtotal: total,
    total: total,
    status: status,
    createdAt: createdAt.millisecondsSinceEpoch,
    updatedAt: updatedAt.millisecondsSinceEpoch,
  );
}
