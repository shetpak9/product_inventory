import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:product_inventory/model/cart.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/home/transaction.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_thumb.dart';
import 'package:product_inventory/shared/option_summary.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/services/activity_log_service.dart';

/// The signed-in customer's cart. Resets itself whenever the user changes.
class CartStore extends ChangeNotifier {
  CartStore._() {
    FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  static final CartStore instance = CartStore._();
  static const int maxQuantity = 99;

  final List<CartItem> _items = <CartItem>[];
  final DatabaseService _database = DatabaseService();
  final ActivityLogService _activityLog = ActivityLogService();
  String? _uid;
  bool _loaded = false;

  List<CartItem> get items => List<CartItem>.unmodifiable(_items);

  /// Total units (used for the cart badge).
  int get itemCount =>
      _items.fold<int>(0, (int sum, CartItem item) => sum + item.quantity);

  double get subtotal => _items.fold<double>(
    0,
    (double sum, CartItem item) => sum + item.lineTotal,
  );

  void _onAuthChanged(User? user) {
    if (user?.uid != _uid) {
      _items.clear();
      _uid = null;
      _loaded = false;
      notifyListeners();
    }
  }

  int _clampQuantity(int quantity) {
    if (quantity < 1) return 1;
    if (quantity > maxQuantity) return maxQuantity;
    return quantity;
  }

  void _replace(String itemId, CartItem Function(CartItem item) update) {
    final int index = _items.indexWhere((CartItem i) => i.id == itemId);
    if (index >= 0) {
      _items[index] = update(_items[index]);
    }
  }

  /// Safe to call many times; only the first call per user hits the database.
  Future<void> load() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _onAuthChanged(null);
      return;
    }
    if (_loaded && _uid == uid) {
      return;
    }

    // No notifyListeners() here: load() is often called from initState.
    _items.clear();
    _uid = uid;
    _loaded = false;

    final List<CartItem> fetched = await _database.getCartItems(uid);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      return;
    }

    _items
      ..clear()
      ..addAll(fetched);
    _loaded = true;
    notifyListeners();
  }

  /// Adds one more of [product], merging with an existing cart line.
  Future<void> addProduct(
    Product product, {
    int quantity = 1,
    Map<String, Object?> selectedOptions = const <String, Object?>{},
    double priceAdjustment = 0,
  }) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('A signed-in user is required to add items to a cart.');
    }

    // Make sure existing lines are known so we merge instead of duplicating.
    await load();

    final int index = _items.indexWhere(
      (CartItem i) =>
          i.productId == product.id &&
          i.optionsIdentity ==
              CartItem(
                id: '',
                productId: product.id,
                productName: product.name,
                price: product.price,
                selectedOptions: selectedOptions,
                priceAdjustment: priceAdjustment,
              ).optionsIdentity,
    );
    if (index >= 0) {
      final CartItem existing = _items[index];
      final int newQuantity = _clampQuantity(existing.quantity + quantity);
      await _database.updateCartItemQuantity(uid, existing.id, newQuantity);
      _replace(existing.id, (CartItem i) => i.copyWith(quantity: newQuantity));
      unawaited(
        _activityLog.logActivity(
          action: 'cart.quantity_updated',
          entityType: 'cart_item',
          entityId: existing.id,
          details: <String, dynamic>{'quantity': newQuantity},
        ),
      );
    } else {
      final CartItem draft = CartItem(
        id: '',
        productId: product.id,
        productName: product.name,
        price: product.price,
        sellerId: product.sellerId,
        storeName: product.storeName,
        imageUrl: product.imageUrl,
        quantity: _clampQuantity(quantity),
        selectedOptions: selectedOptions,
        priceAdjustment: priceAdjustment,
      );
      final String id = await _database.addCartItem(uid, draft);
      _items.add(draft.copyWith(id: id));
      unawaited(
        _activityLog.logActivity(
          action: 'cart.item_added',
          entityType: 'cart_item',
          entityId: id,
          details: <String, dynamic>{'quantity': draft.quantity},
        ),
      );
    }
    notifyListeners();
  }

  Future<void> setQuantity(String itemId, int quantity) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (quantity < 1) {
      await remove(itemId);
      return;
    }

    final int newQuantity = _clampQuantity(quantity);
    await _database.updateCartItemQuantity(uid, itemId, newQuantity);
    _replace(itemId, (CartItem i) => i.copyWith(quantity: newQuantity));
    unawaited(
      _activityLog.logActivity(
        action: 'cart.quantity_updated',
        entityType: 'cart_item',
        entityId: itemId,
        details: <String, dynamic>{'quantity': newQuantity},
      ),
    );
    notifyListeners();
  }

  Future<void> updateItem(CartItem item) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('A signed-in user is required to update the cart.');
    }
    await _database.updateCartItem(uid, item);
    _replace(item.id, (_) => item);
    notifyListeners();
  }

  Future<void> remove(String itemId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _database.removeCartItem(uid, itemId);
    _items.removeWhere((CartItem i) => i.id == itemId);
    unawaited(
      _activityLog.logActivity(
        action: 'cart.item_removed',
        entityType: 'cart_item',
        entityId: itemId,
      ),
    );
    notifyListeners();
  }

  Future<void> clear() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _database.clearCart(uid);
    _items.clear();
    notifyListeners();
  }
}

class Cart extends StatefulWidget {
  const Cart({super.key});

  @override
  State<Cart> createState() => _CartState();
}

class _CartState extends State<Cart> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    CartStore.instance.addListener(_onCartChanged);
    _loadCart();
  }

  @override
  void dispose() {
    CartStore.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCart() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await CartStore.instance.load();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      debugPrint('Cart load failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load your cart. Please try again.';
      });
    }
  }

  Future<void> _updateCart(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('Cart update failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your cart.')),
      );
    }
  }

  Future<void> _checkout() async {
    final List<CartItem> items = CartStore.instance.items;
    if (items.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CheckoutScreen(items: items),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<CartItem> items = CartStore.instance.items;
    final double subtotal = CartStore.instance.subtotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Shopping Cart')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadCart,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Your cart is empty.'),
              ),
            )
          : Column(
              children: <Widget>[
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (BuildContext context, int index) {
                      final CartItem item = items[index];
                      return Card(
                        margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  ProductThumb(url: item.imageUrl, size: 64),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          item.productName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${formatPeso(item.price + item.priceAdjustment)} each · ${formatPeso(item.lineTotal)}',
                                        ),
                                        OptionSummary(
                                          options: item.selectedOptions,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove item',
                                    onPressed: () => _updateCart(
                                      () => CartStore.instance.remove(item.id),
                                    ),
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  IconButton(
                                    tooltip: 'Decrease quantity',
                                    onPressed: () => _updateCart(
                                      () => CartStore.instance.setQuantity(
                                        item.id,
                                        item.quantity - 1,
                                      ),
                                    ),
                                    icon: const Icon(Icons.remove),
                                  ),
                                  Text(item.quantity.toString()),
                                  IconButton(
                                    tooltip: 'Increase quantity',
                                    onPressed:
                                        item.quantity >= CartStore.maxQuantity
                                        ? null
                                        : () => _updateCart(
                                            () =>
                                                CartStore.instance.setQuantity(
                                                  item.id,
                                                  item.quantity + 1,
                                                ),
                                          ),
                                    icon: const Icon(Icons.add),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const Text('Subtotal'),
                            Text('₱${subtotal.toStringAsFixed(2)}'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: ElevatedButton(
                            onPressed: items.isEmpty ? null : _checkout,
                            child: const Text('Check-out'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
