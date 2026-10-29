import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/address.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/store.dart';

void main() {
  test(
    'store writes nested fulfillment settings and reads legacy settings',
    () {
      const Store store = Store(
        ownerId: 'seller',
        name: 'Bakery',
        pickupEnabled: true,
        deliveryEnabled: false,
        deliveryFee: 25,
        leadTimeDays: 2,
        maxAdvanceDays: 45,
        closedDates: <String>['2026-12-25'],
      );

      final Map<String, dynamic> serialized = store.toMap();
      expect(serialized.containsKey('pickupEnabled'), isFalse);
      expect(serialized['fulfillment'], <String, Object?>{
        'pickupEnabled': true,
        'deliveryEnabled': false,
        'deliveryFee': 25,
        'leadTimeDays': 2,
        'maxAdvanceDays': 45,
        'closedDates': <String, bool>{'2026-12-25': true},
      });
      final Store restored = Store.fromMap(serialized, store.ownerId);
      expect(restored.maxAdvanceDays, 45);
      expect(restored.closedDates, <String>['2026-12-25']);

      final Store legacy = Store.fromMap(<String, Object?>{
        'name': 'Legacy',
        'pickupEnabled': false,
        'deliveryEnabled': true,
        'deliveryFee': 40,
        'leadTimeDays': 3,
        'closedDates': <String, bool>{'2026-12-31': true},
      }, 'seller');
      expect(legacy.pickupEnabled, isFalse);
      expect(legacy.deliveryFee, 40);
      expect(legacy.maxAdvanceDays, 30);
      expect(legacy.closedDates, <String>['2026-12-31']);
    },
  );

  test(
    'order fulfillment stores a delivery address snapshot and time slot',
    () {
      final Address address = Address(
        id: 'home',
        label: 'Home',
        recipient: 'A Customer',
        phone: '+63 912 345 6789',
        street: '12 Baker Street',
        barangay: 'Poblacion',
        city: 'Makati',
        province: 'Metro Manila',
        postalCode: '1200',
        notes: 'Call on arrival',
      );
      final OrderFulfillment fulfillment = OrderFulfillment(
        type: FulfillmentType.delivery,
        date: '2026-10-25',
        timeSlot: 'morning',
        address: address.toOrderMap(),
      );

      final OrderFulfillment restored = OrderFulfillment.fromMap(
        fulfillment.toMap(),
      );
      expect(restored.type, FulfillmentType.delivery);
      expect(restored.timeSlotLabel, 'Morning');
      expect(
        restored.addressOneLine,
        '12 Baker Street, Poblacion, Makati, Metro Manila, 1200',
      );
      expect(restored.addressRecipient, 'A Customer');
      expect(restored.addressNotes, 'Call on arrival');
      expect(restored.toMap().containsKey('address'), isTrue);

      final OrderFulfillment pickup = OrderFulfillment(
        type: FulfillmentType.pickup,
        date: '2026-10-25',
        timeSlot: 'afternoon',
      );
      expect(pickup.toMap().containsKey('address'), isFalse);
    },
  );
}
