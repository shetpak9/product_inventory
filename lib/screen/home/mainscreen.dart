import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:product_inventory/screen/home/cart.dart';
import 'package:product_inventory/screen/home/favorites_screen.dart';
import 'package:product_inventory/screen/home/home_screen.dart';
import 'package:product_inventory/screen/home/my_orders.dart';
import 'package:product_inventory/screen/home/shop.dart';
import 'package:product_inventory/screen/account/profile_screen.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/service/favorites_store.dart';
import 'package:product_inventory/service/order_notifier.dart';
import 'package:product_inventory/shared/app_theme.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  String? _notifierUid;

  final List<Widget> _pages = const <Widget>[
    HomeScreen(),
    Shop(),
    FavoritesScreen(),
  ];

  // One Navigator per tab keeps the bottom bar visible on detail pages.
  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List<GlobalKey<NavigatorState>>.generate(
        3,
        (_) => GlobalKey<NavigatorState>(),
      );

  @override
  void initState() {
    super.initState();
    final String? uid = AuthService().currentUser?.uid;
    _notifierUid = uid;
    if (uid != null) {
      unawaited(
        OrderNotifier.instance.startCustomer(
          uid,
          onEvent: _showOrderNotification,
        ),
      );
    }
    unawaited(_preload());
  }

  @override
  void dispose() {
    final String? uid = _notifierUid;
    if (uid != null) unawaited(OrderNotifier.instance.stop(uid));
    super.dispose();
  }

  /// Warms the cart and favorites so badges and hearts are ready.
  Future<void> _preload() async {
    try {
      await Future.wait<void>(<Future<void>>[
        CartStore.instance.load(),
        FavoritesStore.instance.load(),
      ]);
    } catch (error) {
      debugPrint('Preload failed: $error');
    }
  }

  Future<void> _openCart() async {
    await _navigatorKeys[_currentIndex].currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const Cart()),
    );
  }

  Future<void> _openOrders() async {
    OrderNotifier.instance.markOrdersOpened();
    await _navigatorKeys[_currentIndex].currentState?.push(
      MaterialPageRoute<void>(builder: (_) => const MyOrdersScreen()),
    );
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
            _navigatorKeys[_currentIndex].currentState?.push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CustomerOrderDetailScreen(orderId: event.order.id),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openProfile() async {
    final String? uid = AuthService().currentUser?.uid;
    if (uid == null) return;
    await _navigatorKeys[_currentIndex].currentState?.push(
      MaterialPageRoute<void>(builder: (_) => ProfileScreen(uid: uid)),
    );
  }

  Future<void> _signOut() async {
    try {
      await AuthService().signOut();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to log out: $error')));
    }
  }

  /// Back button: close the open page in this tab, else go to Home, else exit.
  Future<void> _handleBack(bool didPop, Object? result) async {
    if (didPop) return;

    final NavigatorState? nested = _navigatorKeys[_currentIndex].currentState;
    if (nested != null && await nested.maybePop()) {
      return;
    }
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: Scaffold(
        appBar: AppBar(
          leading: ListenableBuilder(
            listenable: OrderNotifier.instance,
            builder: (BuildContext context, Widget? child) {
              final bool hasUnseen = OrderNotifier.instance.hasUnseenChanges;
              return PopupMenuButton<String>(
                tooltip: 'Account',
                onSelected: (String value) {
                  if (value == 'orders') _openOrders();
                  if (value == 'profile') _openProfile();
                  if (value == 'logout') _signOut();
                },
                icon: const Icon(Icons.account_circle_outlined),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'orders',
                    child: Row(
                      children: <Widget>[
                        const Expanded(child: Text('My orders')),
                        if (hasUnseen)
                          const _UnseenDot(tooltip: 'New order updates'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'profile',
                    child: Text('Profile'),
                  ),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Text('Log out'),
                  ),
                ],
              );
            },
          ),
          title: const Text(
            kShopName,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          actions: <Widget>[
            ListenableBuilder(
              listenable: CartStore.instance,
              builder: (BuildContext context, Widget? child) {
                final int count = CartStore.instance.itemCount;
                return IconButton(
                  tooltip: 'Shopping cart',
                  onPressed: _openCart,
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                );
              },
            ),
          ],
        ),
        body: IndexedStack(
          index: _currentIndex,
          children: List<Widget>.generate(_pages.length, (int index) {
            return Navigator(
              key: _navigatorKeys[index],
              onGenerateRoute: (RouteSettings settings) =>
                  MaterialPageRoute<void>(
                    settings: settings,
                    builder: (_) => _pages[index],
                  ),
            );
          }),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (int index) {
            setState(() => _currentIndex = index);
          },
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'Shop',
            ),
            NavigationDestination(
              icon: Icon(Icons.favorite_border),
              selectedIcon: Icon(Icons.favorite),
              label: 'Favorites',
            ),
          ],
        ),
      ),
    );
  }
}

class _UnseenDot extends StatelessWidget {
  const _UnseenDot({required this.tooltip});

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: const SizedBox(
        width: 12,
        height: 12,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.pink, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
