import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/service/order_notifier.dart';

void main() {
  const Order order = Order(
    id: 'order-1',
    customerId: 'customer-1',
    customerName: 'Alex',
    sellerId: 'seller-1',
    storeName: 'Bread House',
    items: <OrderItem>[],
    subtotal: 0,
    total: 0,
    status: OrderStatus.baking,
    createdAt: 1,
    updatedAt: 2,
  );

  test('customer status notification describes the new order status', () {
    const OrderNotificationEvent event = OrderNotificationEvent(
      kind: OrderNotificationKind.customerStatusChanged,
      order: order,
      status: OrderStatus.baking,
    );

    expect(event.body, 'Your order from Bread House is now Baking');
  });

  test('seller notification identifies the customer', () {
    const OrderNotificationEvent event = OrderNotificationEvent(
      kind: OrderNotificationKind.sellerNewOrder,
      order: order,
    );

    expect(event.body, 'New order from Alex');
  });
}
