import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:product_inventory/model/address.dart';
import 'package:product_inventory/model/cart.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/model/user.dart';

class ProductDailyLimitException implements Exception {
  const ProductDailyLimitException({
    required this.productName,
    required this.remainingQuantity,
  });

  final String productName;
  final int remainingQuantity;

  @override
  String toString() =>
      '$productName has only $remainingQuantity remaining for that date.';
}

class DatabaseService {
  DatabaseService({FirebaseDatabase? database})
    : _database = database ?? _safeDatabaseInstance();

  static const String _databaseUrl =
      'https://product-inventory-29475-default-rtdb.firebaseio.com';

  static FirebaseDatabase? _safeDatabaseInstance() {
    try {
      return FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );
    } catch (_) {
      return null;
    }
  }

  final FirebaseDatabase? _database;

  DatabaseReference get _db {
    final FirebaseDatabase? db = _database;
    if (db == null) {
      throw StateError('Firebase is not available in this environment.');
    }
    return db.ref();
  }

  DatabaseReference get productRef {
    final FirebaseDatabase? db = _database;
    if (db == null) {
      throw StateError('Firebase is not available in this environment.');
    }
    return db.ref('products');
  }

  DatabaseReference get _storeRef {
    final FirebaseDatabase? db = _database;
    if (db == null) {
      throw StateError('Firebase is not available in this environment.');
    }
    return db.ref('stores');
  }

  DatabaseReference _cartRef(String uid) => _db.child('carts').child(uid);
  DatabaseReference _favoritesRef(String uid) =>
      _db.child('favorites').child(uid);
  // ---------------------------------------------------------------- users

  Future<void> createUserProfile(UserData user) async {
    // set() completes only after the server accepts the write, and throws if
    // the security rules reject it, so no read-back is needed.
    await _db.child('users').child(user.uid).set(user.toMap());
  }

  Future<UserData?> getUserProfile(String uid) async {
    final DataSnapshot snapshot = await _db.child('users').child(uid).get();
    final Object? raw = snapshot.value;
    return raw is Map ? UserData.fromMap(raw, uid) : null;
  }

  Future<void> updateUserProfile(
    String uid, {
    required String firstName,
    required String lastName,
    required String phone,
  }) {
    return _db.child('users').child(uid).update(<String, Object?>{
      'firstName': firstName.trim(),
      'lastName': lastName.trim(),
      'phone': phone.trim().isEmpty ? null : phone.trim(),
    });
  }

  Stream<List<Address>> addressesStream(String uid) {
    return _db.child('addresses').child(uid).onValue.map((DatabaseEvent event) {
      final Object? raw = event.snapshot.value;
      if (raw is! Map) return <Address>[];
      final List<Address> addresses = <Address>[];
      for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
        if (entry.value is Map) {
          addresses.add(
            Address.fromMap(entry.value as Map, entry.key.toString()),
          );
        }
      }
      addresses.sort((Address a, Address b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
      return addresses;
    });
  }

  Future<List<Address>> getAddressesOnce(String uid) async {
    final DataSnapshot snapshot = await _db.child('addresses').child(uid).get();
    final Object? raw = snapshot.value;
    if (raw is! Map) return <Address>[];
    final List<Address> addresses = <Address>[];
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      if (entry.value is Map) {
        addresses.add(
          Address.fromMap(entry.value as Map, entry.key.toString()),
        );
      }
    }
    addresses.sort((Address a, Address b) {
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return addresses;
  }

  Future<String> saveAddress(String uid, Address address) async {
    final DatabaseReference addressesRef = _db.child('addresses').child(uid);
    final DataSnapshot snapshot = await addressesRef.get();
    final Object? raw = snapshot.value;
    final Map<dynamic, dynamic> existing = raw is Map
        ? raw
        : <dynamic, dynamic>{};
    final bool isNew = address.id.isEmpty;
    if (isNew && existing.length >= 10) {
      throw StateError('You can save up to 10 addresses.');
    }
    final String id = isNew
        ? (addressesRef.push().key ??
              (throw StateError('Could not generate an address id.')))
        : address.id;
    final bool hasDefault = existing.values.any(
      (dynamic value) => value is Map && value['isDefault'] == true,
    );
    final bool makeDefault =
        address.isDefault || existing.isEmpty || !hasDefault;
    final Map<String, Object?> updates = <String, Object?>{
      'addresses/$uid/$id': <String, Object?>{
        ...address.toMap(),
        'isDefault': makeDefault,
        'updatedAt': ServerValue.timestamp,
      },
    };
    if (makeDefault) {
      for (final dynamic key in existing.keys) {
        if (key.toString() != id) {
          updates['addresses/$uid/$key/isDefault'] = false;
        }
      }
    }
    await _db.update(updates);
    return id;
  }

  Future<void> deleteAddress(String uid, String addressId) async {
    final DatabaseReference addressesRef = _db.child('addresses').child(uid);
    final DataSnapshot snapshot = await addressesRef.get();
    final Object? raw = snapshot.value;
    if (raw is! Map || !raw.containsKey(addressId)) return;
    final Object? removedRaw = raw[addressId];
    final bool wasDefault =
        removedRaw is Map && removedRaw['isDefault'] == true;
    final Map<String, Object?> updates = <String, Object?>{
      'addresses/$uid/$addressId': null,
    };
    if (wasDefault) {
      final Iterable<MapEntry<dynamic, dynamic>> remaining = raw.entries.where(
        (MapEntry<dynamic, dynamic> entry) => entry.key != addressId,
      );
      final MapEntry<dynamic, dynamic>? next = remaining.isEmpty
          ? null
          : remaining.first;
      for (final MapEntry<dynamic, dynamic> entry in remaining) {
        updates['addresses/$uid/${entry.key}/isDefault'] =
            entry.key == next?.key;
      }
    }
    await _db.update(updates);
  }

  Future<void> setDefaultAddress(String uid, String addressId) async {
    final DatabaseReference addressesRef = _db.child('addresses').child(uid);
    final DataSnapshot snapshot = await addressesRef.get();
    final Object? raw = snapshot.value;
    if (raw is! Map || !raw.containsKey(addressId)) {
      throw StateError('That saved address no longer exists.');
    }
    final Map<String, Object?> updates = <String, Object?>{};
    for (final dynamic key in raw.keys) {
      updates['addresses/$uid/$key/isDefault'] = key.toString() == addressId;
    }
    await _db.update(updates);
  }

  Future<bool> hasActiveOrders(String uid, UserRole role) async {
    final Query query = _db
        .child('orders')
        .orderByChild(role == UserRole.customer ? 'customerId' : 'sellerId')
        .equalTo(uid);
    final DataSnapshot snapshot = await query.get();
    final Object? raw = snapshot.value;
    if (raw is! Map) return false;
    for (final Object? value in raw.values) {
      if (value is! Map) continue;
      final OrderStatus status = OrderStatus.fromDbValue(
        value['status']?.toString(),
      );
      if (status != OrderStatus.delivered && status != OrderStatus.cancelled) {
        return true;
      }
    }
    return false;
  }

  Future<void> deleteAccountData(String uid, UserRole role) async {
    await _favoritesRef(uid).remove();
    await _cartRef(uid).remove();
    await _db.child('addresses').child(uid).remove();
    if (role == UserRole.seller) {
      final DataSnapshot products = await productRef
          .orderByChild('sellerId')
          .equalTo(uid)
          .get();
      final Object? rawProducts = products.value;
      if (rawProducts is Map) {
        for (final dynamic productId in rawProducts.keys) {
          await productRef.child(productId.toString()).remove();
        }
      }
      await _storeRef.child(uid).remove();
    }
    await _db.child('users').child(uid).remove();
  }

  /// Emits null while the profile doesn't exist yet (e.g. mid-registration).
  Stream<UserData?> userProfileStream(String uid) {
    return _db.child('users').child(uid).onValue.map((DatabaseEvent event) {
      final Object? raw = event.snapshot.value;
      return raw is Map ? UserData.fromMap(raw, uid) : null;
    });
  }

  // --------------------------------------------------------------- stores

  Stream<Store?> storeStream(String ownerId) {
    return _storeRef.child(ownerId).onValue.map((DatabaseEvent event) {
      final Object? raw = event.snapshot.value;
      return raw is Map ? Store.fromMap(raw, ownerId) : null;
    });
  }

  Future<Store?> getStore(String ownerId) async {
    final DataSnapshot snapshot = await _storeRef.child(ownerId).get();
    final Object? raw = snapshot.value;
    return raw is Map ? Store.fromMap(raw, ownerId) : null;
  }

  /// Every store, sorted by name. Customers use this to browse stores.
  Stream<List<Store>> get storesStream {
    return _storeRef.onValue.map((DatabaseEvent event) {
      final Object? raw = event.snapshot.value;
      if (raw is! Map) {
        return <Store>[];
      }

      final List<Store> stores = <Store>[];
      for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
        final Object? value = entry.value;
        if (value is Map) {
          stores.add(Store.fromMap(value, entry.key.toString()));
        }
      }
      stores.sort(
        (Store a, Store b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return stores;
    });
  }

  /// One-time check used before adding to the cart. Products without a
  /// seller (older test data) and missing stores count as open.
  Future<bool> isStoreOpen(String sellerId) async {
    if (sellerId.isEmpty) {
      return true;
    }
    final DataSnapshot snapshot = await _storeRef
        .child(sellerId)
        .child('isOpen')
        .get();
    final Object? value = snapshot.value;
    return value is bool ? value : true;
  }

  /// Creates or updates the store, and keeps the denormalised `storeName`
  /// on the seller's products in sync, all in one atomic multi-path update.
  Future<void> saveStore(Store store) async {
    final Map<String, Object?> updates = <String, Object?>{
      'stores/${store.ownerId}': <String, Object?>{
        ...store.toMap(),
        'updatedAt': ServerValue.timestamp,
      },
    };

    final DataSnapshot existing = await productRef
        .orderByChild('sellerId')
        .equalTo(store.ownerId)
        .get();
    final Object? raw = existing.value;
    if (raw is Map) {
      for (final dynamic productId in raw.keys) {
        updates['products/$productId/storeName'] = store.name;
      }
    }

    await _db.update(updates);
  }

  // ------------------------------------------------------------- products

  List<Product> _productsFromSnapshot(DataSnapshot snapshot) {
    final Object? raw = snapshot.value;
    if (raw is! Map) {
      return <Product>[];
    }

    final List<Product> products = <Product>[];
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      final Object? value = entry.value;
      if (value is Map) {
        products.add(Product.fromMap(value, entry.key.toString()));
      }
    }
    products.sort(
      (Product a, Product b) =>
          a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return products;
  }

  /// What customers see: only products the seller hasn't hidden.
  Stream<List<Product>> get products {
    return productRef.onValue.map(
      (DatabaseEvent event) => _productsFromSnapshot(
        event.snapshot,
      ).where((Product p) => p.isAvailable).toList(),
    );
  }

  Stream<Product?> getProduct(String productId) {
    return productRef.child(productId).onValue.map((DatabaseEvent event) {
      final Object? raw = event.snapshot.value;
      return raw is Map ? Product.fromMap(raw, productId) : null;
    });
  }

  Future<Product?> getProductOnce(String productId) async {
    final DataSnapshot snapshot = await productRef.child(productId).get();
    final Object? raw = snapshot.value;
    return raw is Map ? Product.fromMap(raw, productId) : null;
  }

  /// Every product of one seller, including hidden ones.
  Stream<List<Product>> sellerProductsStream(String sellerId) {
    return productRef
        .orderByChild('sellerId')
        .equalTo(sellerId)
        .onValue
        .map((DatabaseEvent event) => _productsFromSnapshot(event.snapshot));
  }

  String newProductId() {
    final String? key = productRef.push().key;
    if (key == null) {
      throw StateError('Could not generate a product id.');
    }
    return key;
  }

  Future<void> saveProduct(Product product) async {
    await productRef.child(product.id).set(<String, Object?>{
      ...product.toMap(),
      'updatedAt': ServerValue.timestamp,
    });
  }

  Future<void> setProductAvailability(String productId, bool isAvailable) {
    return productRef.child(productId).update(<String, Object?>{
      'isAvailable': isAvailable,
    });
  }

  Future<void> deleteProduct(String productId) {
    return productRef.child(productId).remove();
  }

  // ----------------------------------------------------------------- cart

  Future<List<CartItem>> getCartItems(String uid) async {
    final DataSnapshot snapshot = await _cartRef(uid).get();
    final Object? raw = snapshot.value;
    if (raw is! Map) {
      return <CartItem>[];
    }
    return raw.entries.map((MapEntry<dynamic, dynamic> entry) {
      return CartItem.fromMap(entry.value as Map, entry.key.toString());
    }).toList();
  }

  Future<String> addCartItem(String uid, CartItem item) async {
    final DatabaseReference itemRef = _cartRef(uid).push();
    await itemRef.set(item.toMap());
    return itemRef.key!;
  }

  Future<void> removeCartItem(String uid, String itemId) {
    return _cartRef(uid).child(itemId).remove();
  }

  Future<void> clearCart(String uid) => _cartRef(uid).remove();

  Future<void> updateCartItemQuantity(String uid, String itemId, int quantity) {
    return _cartRef(
      uid,
    ).child(itemId).update(<String, Object?>{'quantity': quantity});
  }

  Future<void> updateCartItem(String uid, CartItem item) {
    return _cartRef(uid).child(item.id).set(item.toMap());
  }

  // ------------------------------------------------------------ favorites
  // favorites/{uid}/{productId} = true

  Future<Set<String>> getFavoriteIds(String uid) async {
    final DataSnapshot snapshot = await _favoritesRef(uid).get();
    final Object? raw = snapshot.value;
    if (raw is! Map) {
      return <String>{};
    }
    return raw.keys.map((dynamic key) => key.toString()).toSet();
  }

  Future<void> addFavorite(String uid, String productId) {
    return _favoritesRef(uid).child(productId).set(true);
  }

  Future<void> removeFavorite(String uid, String productId) {
    return _favoritesRef(uid).child(productId).remove();
  }

  // ------------------------------------------------------------------ orders

  Future<List<String>> placeOrders(List<Order> orders) async {
    if (orders.isEmpty) {
      throw ArgumentError('At least one order is required.');
    }

    final List<_ProductCountReservation> reservations =
        <_ProductCountReservation>[];
    try {
      final Map<String, _ProductCountReservation> requestedCounts =
          <String, _ProductCountReservation>{};
      for (final Order order in orders) {
        final String date = order.fulfillment.date;
        for (final OrderItem item in order.items) {
          final String key = '${item.productId}/$date';
          final _ProductCountReservation? existing = requestedCounts[key];
          requestedCounts[key] = _ProductCountReservation(
            productId: item.productId,
            date: date,
            quantity: (existing?.quantity ?? 0) + item.quantity,
            maxPerDay: existing?.maxPerDay,
            productName: item.productName,
          );
        }
      }
      for (final _ProductCountReservation request in requestedCounts.values) {
        final Product? product = await getProductOnce(request.productId);
        if (product == null) {
          throw StateError('${request.productName} is no longer available.');
        }
        final _ProductCountReservation reservation = request.withLimit(
          product.maxPerDay,
          product.name,
        );
        await _adjustProductCount(
          reservation,
          reservation.quantity,
          enforceLimit: true,
        );
        reservations.add(reservation);
      }

      final Map<String, Object?> updates = <String, Object?>{};
      final List<String> orderIds = <String>[];
      for (final Order order in orders) {
        final String? orderId = _db.child('orders').push().key;
        if (orderId == null) {
          throw StateError('Could not generate an order id.');
        }
        orderIds.add(orderId);
        updates['orders/$orderId'] = <String, Object?>{
          ...order.toMap(),
          'createdAt': ServerValue.timestamp,
          'updatedAt': ServerValue.timestamp,
        };
      }
      try {
        await _db.update(updates);
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied' ||
            error.message?.toLowerCase().contains('permission denied') ==
                true) {
          throw StateError(
            'Firebase denied the order write. Publish the current '
            'database.rules.json and verify the signed-in customer, store, '
            'product, and fulfillment data are valid.',
          );
        }
        rethrow;
      }
      return orderIds;
    } catch (error) {
      for (final _ProductCountReservation reservation
          in reservations.reversed) {
        try {
          await _adjustProductCount(reservation, -reservation.quantity);
        } catch (rollbackError) {
          debugPrint(
            'Could not roll back product count reservation '
            'for ${reservation.productId}/${reservation.date}: $rollbackError',
          );
        }
      }
      rethrow;
    }
  }

  Stream<List<Order>> customerOrdersStream(String uid) {
    return _db
        .child('orders')
        .orderByChild('customerId')
        .equalTo(uid)
        .onValue
        .map((DatabaseEvent event) => _ordersFromSnapshot(event.snapshot));
  }

  Stream<List<Order>> sellerOrdersStream(String sellerId) {
    return _db
        .child('orders')
        .orderByChild('sellerId')
        .equalTo(sellerId)
        .onValue
        .map((DatabaseEvent event) => _ordersFromSnapshot(event.snapshot));
  }

  Stream<Order?> orderStream(String orderId) {
    return _db.child('orders').child(orderId).onValue.map((
      DatabaseEvent event,
    ) {
      final Object? raw = event.snapshot.value;
      return raw is Map ? Order.fromMap(raw, orderId) : null;
    });
  }

  Future<void> updateOrderStatus(String orderId, OrderStatus status) async {
    Order? order;
    if (status == OrderStatus.cancelled) {
      final DataSnapshot snapshot = await _db
          .child('orders')
          .child(orderId)
          .get();
      final Object? raw = snapshot.value;
      if (raw is Map) {
        order = Order.fromMap(raw, orderId);
      }
    }
    await _db.child('orders').child(orderId).update(<String, Object?>{
      'status': status.dbValue,
      'updatedAt': ServerValue.timestamp,
    });
    final Order? cancelledOrder = order;
    if (status != OrderStatus.cancelled ||
        cancelledOrder == null ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}$',
        ).hasMatch(cancelledOrder.fulfillment.date)) {
      return;
    }
    final Map<String, int> quantities = <String, int>{};
    for (final OrderItem item in cancelledOrder.items) {
      quantities.update(
        item.productId,
        (int quantity) => quantity + item.quantity,
        ifAbsent: () => item.quantity,
      );
    }
    Object? firstCountError;
    for (final MapEntry<String, int> entry in quantities.entries) {
      try {
        await _adjustProductCount(
          _ProductCountReservation(
            productId: entry.key,
            date: cancelledOrder.fulfillment.date,
            quantity: entry.value,
            productName: cancelledOrder.items
                .firstWhere((OrderItem item) => item.productId == entry.key)
                .productName,
          ),
          -entry.value,
        );
      } catch (error) {
        firstCountError ??= error;
        debugPrint(
          'Order $orderId was cancelled, but its daily count for '
          '${entry.key} could not be decremented: $error',
        );
      }
    }
    if (firstCountError != null) {
      throw StateError(
        'The order was cancelled, but one or more daily product counts could not be updated: '
        '$firstCountError',
      );
    }
  }

  Future<void> _adjustProductCount(
    _ProductCountReservation reservation,
    int quantity, {
    bool enforceLimit = false,
  }) async {
    final DatabaseReference countRef = _db
        .child('productCounts')
        .child(reservation.productId)
        .child(reservation.date);
    int? remaining;
    final TransactionResult result = await countRef.runTransaction((
      Object? value,
    ) {
      final int current = value is num ? value.toInt() : 0;
      final int updated = current + quantity;
      if (updated < 0) {
        remaining = current;
        return Transaction.abort();
      }
      final int? limit = reservation.maxPerDay;
      if (enforceLimit && limit != null && updated > limit) {
        remaining = (limit - current).clamp(0, limit);
        return Transaction.abort();
      }
      return Transaction.success(updated);
    }, applyLocally: false);

    if (!result.committed) {
      if (enforceLimit && reservation.maxPerDay != null) {
        throw ProductDailyLimitException(
          productName: reservation.productName,
          remainingQuantity: remaining ?? 0,
        );
      }
      throw StateError(
        'Could not update the daily count for ${reservation.productName}.',
      );
    }
  }

  List<Order> _ordersFromSnapshot(DataSnapshot snapshot) {
    final Object? raw = snapshot.value;
    if (raw is! Map) {
      return <Order>[];
    }
    final List<Order> orders = <Order>[];
    for (final MapEntry<dynamic, dynamic> entry in raw.entries) {
      if (entry.value is Map) {
        orders.add(Order.fromMap(entry.value as Map, entry.key.toString()));
      }
    }

    orders.sort(
      (Order a, Order b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0),
    );
    return orders;
  }
}

class _ProductCountReservation {
  const _ProductCountReservation({
    required this.productId,
    required this.date,
    required this.quantity,
    required this.productName,
    this.maxPerDay,
  });

  final String productId;
  final String date;
  final int quantity;
  final String productName;
  final int? maxPerDay;

  _ProductCountReservation withLimit(int? limit, String currentProductName) {
    return _ProductCountReservation(
      productId: productId,
      date: date,
      quantity: quantity,
      productName: currentProductName,
      maxPerDay: limit,
    );
  }
}
