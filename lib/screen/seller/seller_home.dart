import 'dart:async';

import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/screen/account/profile_screen.dart';
import 'package:product_inventory/screen/seller/product_form.dart';
import 'package:product_inventory/screen/seller/promotions.dart';
import 'package:product_inventory/screen/seller/seller_dashboard.dart';
import 'package:product_inventory/screen/seller/seller_orders.dart';
import 'package:product_inventory/screen/seller/store_setup.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/order_notifier.dart';
import 'package:product_inventory/service/storage_service.dart';
import 'package:product_inventory/shared/product_thumb.dart';

class SellerHome extends StatefulWidget {
  const SellerHome({super.key, required this.profile});

  final UserData profile;

  @override
  State<SellerHome> createState() => _SellerHomeState();
}

class _SellerHomeState extends State<SellerHome> {
  final DatabaseService _db = DatabaseService();
  final StorageService _storage = StorageService();
  int _selectedTab = 0;
  String? _notifierUid;

  // Created once; see the note about streams inside build().
  late final Stream<Store?> _storeStream = _db.storeStream(widget.profile.uid);
  late final Stream<List<Product>> _productsStream = _db.sellerProductsStream(
    widget.profile.uid,
  );
  late final Stream<List<Order>> _ordersStream = _db.sellerOrdersStream(
    widget.profile.uid,
  );

  @override
  void initState() {
    super.initState();
    _notifierUid = widget.profile.uid;
    unawaited(
      OrderNotifier.instance.startSeller(
        widget.profile.uid,
        onEvent: _showOrderNotification,
      ),
    );
  }

  @override
  void dispose() {
    final String? uid = _notifierUid;
    if (uid != null) unawaited(OrderNotifier.instance.stop(uid));
    super.dispose();
  }

  void _showOrderNotification(OrderNotificationEvent event) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(event.body),
        action: SnackBarAction(
          label: 'View',
          onPressed: () {
            OrderNotifier.instance.markOrdersOpened();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SellerOrderDetailScreen(orderId: event.order.id),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openStoreSetup(Store? existing) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StoreSetupScreen(ownerId: widget.profile.uid, existing: existing),
      ),
    );
  }

  void _openProductForm(Store store, {Product? product}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductFormScreen(
          sellerId: widget.profile.uid,
          storeName: store.name,
          product: product,
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setAvailability(Product product, bool value) async {
    try {
      await _db.setProductAvailability(product.id, value);
    } catch (e) {
      _showError('Could not update ${product.name}: $e');
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('"${product.name}" will be removed from your store.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _db.deleteProduct(product.id);
      final String? url = product.imageUrl;
      if (url != null && url.isNotEmpty) {
        await _storage.deleteByUrl(url);
      }
    } catch (e) {
      _showError('Could not delete ${product.name}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Store?>(
      stream: _storeStream,
      builder: (BuildContext context, AsyncSnapshot<Store?> storeSnapshot) {
        if (storeSnapshot.hasError) {
          return _Message(
            text: 'Could not load your store.\n${storeSnapshot.error}',
            onSignOut: () => AuthService().signOut(),
          );
        }
        if (storeSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final Store? store = storeSnapshot.data;
        if (store == null) {
          return _Message(
            text:
                'Welcome, ${widget.profile.firstName}!\n'
                'Set up your store to start posting products.',
            actionLabel: 'Set up store',
            onAction: () => _openStoreSetup(null),
            onSignOut: () => AuthService().signOut(),
          );
        }

        return StreamBuilder<List<Order>>(
          stream: _ordersStream,
          builder:
              (
                BuildContext context,
                AsyncSnapshot<List<Order>> ordersSnapshot,
              ) {
                final int pendingCount =
                    ordersSnapshot.data
                        ?.where(
                          (Order order) => order.status == OrderStatus.pending,
                        )
                        .length ??
                    0;
                return Scaffold(
                  backgroundColor: const Color(0xFFFDF8F0),
                  appBar: AppBar(
                    backgroundColor: Colors.brown[100],
                    title: Text(store.name),
                    actions: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.storefront_outlined),
                        tooltip: 'Edit store',
                        onPressed: () => _openStoreSetup(store),
                      ),
                      IconButton(
                        icon: const Icon(Icons.account_circle_outlined),
                        tooltip: 'Profile',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ProfileScreen(uid: widget.profile.uid),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'Log out',
                        onPressed: () => AuthService().signOut(),
                      ),
                    ],
                  ),
                  floatingActionButton: _selectedTab == 3
                      ? FloatingActionButton.extended(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PromotionFormScreen(
                                sellerId: widget.profile.uid,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('Add promotion'),
                        )
                      : _selectedTab == 0
                      ? FloatingActionButton.extended(
                          onPressed: () => _openProductForm(store),
                          icon: const Icon(Icons.add),
                          label: const Text('Add product'),
                        )
                      : null,
                  body: StreamBuilder<List<Product>>(
                    stream: _productsStream,
                    builder:
                        (
                          BuildContext context,
                          AsyncSnapshot<List<Product>> productSnapshot,
                        ) => IndexedStack(
                          index: _selectedTab,
                          children: <Widget>[
                            _buildProducts(store, productSnapshot),
                            SellerOrdersTab(
                              orders: ordersSnapshot.data,
                              loading:
                                  ordersSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !ordersSnapshot.hasData &&
                                  !ordersSnapshot.hasError,
                              error: ordersSnapshot.error,
                            ),
                            SellerDashboardTab(
                              orders: ordersSnapshot.data,
                              products: productSnapshot.data,
                              loading:
                                  ordersSnapshot.connectionState ==
                                      ConnectionState.waiting &&
                                  !ordersSnapshot.hasData &&
                                  !ordersSnapshot.hasError,
                              error: ordersSnapshot.error,
                            ),
                            SellerPromotionsTab(sellerId: widget.profile.uid),
                          ],
                        ),
                  ),
                  bottomNavigationBar: ListenableBuilder(
                    listenable: OrderNotifier.instance,
                    builder: (BuildContext context, Widget? child) =>
                        NavigationBar(
                          selectedIndex: _selectedTab,
                          onDestinationSelected: (int index) {
                            if (index == 1) {
                              OrderNotifier.instance.markOrdersOpened();
                            }
                            setState(() => _selectedTab = index);
                          },
                          destinations: <NavigationDestination>[
                            const NavigationDestination(
                              icon: Icon(Icons.inventory_2_outlined),
                              selectedIcon: Icon(Icons.inventory_2),
                              label: 'Products',
                            ),
                            NavigationDestination(
                              icon: _ordersTabIcon(
                                pendingCount,
                                selected: false,
                                hasUnseen:
                                    OrderNotifier.instance.hasUnseenChanges,
                              ),
                              selectedIcon: _ordersTabIcon(
                                pendingCount,
                                selected: true,
                                hasUnseen:
                                    OrderNotifier.instance.hasUnseenChanges,
                              ),
                              label: 'Orders',
                            ),
                            const NavigationDestination(
                              icon: Icon(Icons.dashboard_outlined),
                              selectedIcon: Icon(Icons.dashboard),
                              label: 'Dashboard',
                            ),
                            const NavigationDestination(
                              icon: Icon(Icons.local_offer_outlined),
                              selectedIcon: Icon(Icons.local_offer),
                              label: 'Promos',
                            ),
                          ],
                        ),
                  ),
                );
              },
        );
      },
    );
  }

    Widget _buildProducts(
    Store store,
    AsyncSnapshot<List<Product>> snapshot,
  ) {
    if (snapshot.hasError) {
      return Center(
        child: Text('Unable to load products: ${snapshot.error}'),
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Product> products = snapshot.data!;
    if (products.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No products yet.\nTap "Add product" to post your first one.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final Product product = products[index];
        final List<String> details = <String>[
          '₱${product.price.toStringAsFixed(2)}',
          if (product.category.isNotEmpty) product.category,
          if (product.stockQuantity != null)
            product.stockQuantity == 0
                ? 'Out of stock'
                : product.stockQuantity! <= 5
                ? 'Low stock (${product.stockQuantity})'
                : '${product.stockQuantity} in stock',
          if (!product.isAvailable) 'Hidden',
        ];

        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            onTap: () => _openProductForm(store, product: product),
            leading: ProductThumb(url: product.imageUrl),
            title: Text(product.name),
            subtitle: Text(details.join(' · ')),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Switch(
                  value: product.isAvailable,
                  onChanged: (bool v) => _setAvailability(product, v),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(product),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _ordersTabIcon(
    int pendingCount, {
    required bool selected,
    required bool hasUnseen,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: Icon(
            selected ? Icons.receipt_long : Icons.receipt_long_outlined,
          ),
        ),
        if (hasUnseen)
          Positioned(
            right: -2,
            top: -3,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Colors.pink,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    required this.onSignOut,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final String? label = actionLabel;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(text, textAlign: TextAlign.center),
              if (label != null) ...<Widget>[
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onAction,
                  child: Text(label),
                ),
              ],
              const SizedBox(height: 12),
              TextButton(onPressed: onSignOut, child: const Text('Sign out')),
            ],
          ),
        ),
      ),
    );
  }
}
