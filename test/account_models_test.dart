import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/address.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/user.dart';

void main() {
  test('saved address round-trips and formats its location', () {
    const Address address = Address(
      id: 'home',
      label: 'Home',
      recipient: 'A. Customer',
      phone: '+63 912 345 6789',
      street: '12 Baker Street',
      barangay: 'Poblacion',
      city: 'Makati',
      province: 'Metro Manila',
      postalCode: '1200',
      notes: 'Gate is beside the bakery.',
      isDefault: true,
      updatedAt: 1234,
    );

    final Address restored = Address.fromMap(address.toMap(), address.id);
    expect(restored.label, address.label);
    expect(restored.phone, address.phone);
    expect(
      restored.oneLine,
      '12 Baker Street, Poblacion, Makati, Metro Manila, 1200',
    );
    expect(restored.isDefault, isTrue);
    expect(restored.updatedAt, 1234);
  });

  test('user profile phone is optional and round-trips when present', () {
    const UserData withPhone = UserData(
      uid: 'customer',
      firstName: 'Test',
      lastName: 'Customer',
      phone: '+63 912 345 6789',
    );
    final UserData restored = UserData.fromMap(
      withPhone.toMap(),
      withPhone.uid,
    );

    expect(restored.phone, withPhone.phone);
    expect(
      UserData.fromMap(<String, Object?>{
        'firstName': 'Test',
      }, 'customer').phone,
      isNull,
    );
  });

  test('order preserves the customer phone for the seller', () {
    final Order order = Order(
      id: 'order',
      customerId: 'customer',
      customerName: 'Test Customer',
      customerPhone: '+63 912 345 6789',
      sellerId: 'seller',
      storeName: 'Bakery',
      items: const <OrderItem>[],
      subtotal: 0,
      total: 0,
      status: OrderStatus.pending,
      createdAt: 1,
      updatedAt: 1,
    );

    final Order restored = Order.fromMap(order.toMap(), order.id);
    expect(restored.customerPhone, order.customerPhone);
  });
}
