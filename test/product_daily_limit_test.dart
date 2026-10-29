import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';

void main() {
  group('Product daily limit', () {
    test('is optional and round-trips when set', () {
      final Product unlimited = Product.fromMap(<String, Object?>{
        'name': 'Bread',
        'price': 25,
      }, 'bread');
      expect(unlimited.maxPerDay, isNull);

      final Product limited = Product.fromMap(<String, Object?>{
        'name': 'Bread',
        'price': 25,
        'maxPerDay': 12,
      }, 'bread');
      expect(limited.maxPerDay, 12);
      expect(limited.toMap()['maxPerDay'], 12);
    });
  });

  group('Pickup order status', () {
    test('skips out for delivery after ready', () {
      expect(
        nextStatuses(
          OrderStatus.ready,
          fulfillmentType: FulfillmentType.pickup,
        ),
        <OrderStatus>[OrderStatus.delivered],
      );
    });

    test('delivery orders retain out-for-delivery transition', () {
      expect(
        nextStatuses(
          OrderStatus.ready,
          fulfillmentType: FulfillmentType.delivery,
        ),
        <OrderStatus>[OrderStatus.outForDelivery, OrderStatus.delivered],
      );
    });
  });
}
