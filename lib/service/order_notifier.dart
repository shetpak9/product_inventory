import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/service/database.dart';

enum OrderNotificationKind { customerStatusChanged, sellerNewOrder }

class OrderNotificationEvent {
  const OrderNotificationEvent({
    required this.kind,
    required this.order,
    this.status,
  });

  final OrderNotificationKind kind;
  final Order order;
  final OrderStatus? status;

  String get title => switch (kind) {
    OrderNotificationKind.customerStatusChanged => 'Order update',
    OrderNotificationKind.sellerNewOrder => 'New order',
  };

  String get body => switch (kind) {
    OrderNotificationKind.customerStatusChanged =>
      'Your order from ${order.storeName} is now ${status?.label ?? order.status.label}',
    OrderNotificationKind.sellerNewOrder =>
      'New order from ${order.customerName}',
  };
}

class OrderNotifier extends ChangeNotifier {
  OrderNotifier._();

  static final OrderNotifier instance = OrderNotifier._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final DatabaseService _database = DatabaseService();
  StreamSubscription<List<Order>>? _subscription;
  String? _activeUid;
  bool? _isSeller;
  bool _initialized = false;
  bool _permissionRequested = false;
  bool _hasUnseenChanges = false;
  bool _hasBaseline = false;
  int _notificationId = 0;
  Map<String, OrderStatus> _previousStatuses = <String, OrderStatus>{};
  Map<String, Order> _previousOrders = <String, Order>{};
  void Function(OrderNotificationEvent event)? _onEvent;
  Future<void>? _initialization;

  bool get hasUnseenChanges => _hasUnseenChanges;

  Future<void> initialize() async {
    if (_initialized) return;
    final Future<void>? pendingInitialization = _initialization;
    if (pendingInitialization != null) {
      await pendingInitialization;
      return;
    }
    final Future<void> initialization = _initializePlugin();
    _initialization = initialization;
    try {
      await initialization;
    } finally {
      _initialization = null;
    }
  }

  Future<void> _initializePlugin() async {
    const InitializationSettings settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_order_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );
    await _notifications.initialize(settings: settings);
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'order_updates',
      'Order updates',
      description: 'Notifications about customer and seller order updates.',
      importance: Importance.defaultImportance,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    _initialized = true;
  }

  Future<void> startCustomer(
    String uid, {
    required void Function(OrderNotificationEvent event) onEvent,
  }) => _start(uid, isSeller: false, onEvent: onEvent);

  Future<void> startSeller(
    String uid, {
    required void Function(OrderNotificationEvent event) onEvent,
  }) => _start(uid, isSeller: true, onEvent: onEvent);

  Future<void> _start(
    String uid, {
    required bool isSeller,
    required void Function(OrderNotificationEvent event) onEvent,
  }) async {
    if (_activeUid == uid && _isSeller == isSeller) return;
    final StreamSubscription<List<Order>>? previousSubscription = _subscription;
    _subscription = null;
    _activeUid = uid;
    _isSeller = isSeller;
    _onEvent = onEvent;
    _hasBaseline = false;
    _previousStatuses = <String, OrderStatus>{};
    _previousOrders = <String, Order>{};
    await previousSubscription?.cancel();
    if (_activeUid != uid || _isSeller != isSeller) return;

    try {
      await initialize();
      await _requestPermissionAfterSignIn();
    } catch (error) {
      debugPrint('Order notification setup failed: $error');
    }
    if (_activeUid != uid || _isSeller != isSeller) return;
    try {
      final Stream<List<Order>> orderStream = isSeller
          ? _database.sellerOrdersStream(uid)
          : _database.customerOrdersStream(uid);
      _subscription = orderStream.listen(
        _handleOrders,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Order notification stream failed: $error');
        },
      );
    } catch (error) {
      debugPrint('Could not start order notification stream: $error');
    }
  }

  Future<void> _requestPermissionAfterSignIn() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    final AndroidFlutterLocalNotificationsPlugin? android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.requestNotificationsPermission();
      return;
    }
    final IOSFlutterLocalNotificationsPlugin? ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  void _handleOrders(List<Order> orders) {
    if (!_hasBaseline) {
      _remember(orders);
      _hasBaseline = true;
      return;
    }

    final bool isSeller = _isSeller ?? false;
    for (final Order order in orders) {
      if (isSeller) {
        if (!_previousOrders.containsKey(order.id) &&
            order.status == OrderStatus.pending) {
          _publish(
            OrderNotificationEvent(
              kind: OrderNotificationKind.sellerNewOrder,
              order: order,
            ),
          );
        }
      } else {
        final OrderStatus? previousStatus = _previousStatuses[order.id];
        if (previousStatus != null && previousStatus != order.status) {
          _publish(
            OrderNotificationEvent(
              kind: OrderNotificationKind.customerStatusChanged,
              order: order,
              status: order.status,
            ),
          );
        }
      }
    }
    _remember(orders);
  }

  void _remember(List<Order> orders) {
    _previousStatuses = <String, OrderStatus>{
      for (final Order order in orders) order.id: order.status,
    };
    _previousOrders = <String, Order>{
      for (final Order order in orders) order.id: order,
    };
  }

  void _publish(OrderNotificationEvent event) {
    _hasUnseenChanges = true;
    notifyListeners();
    _onEvent?.call(event);
    unawaited(_showNotification(event));
  }

  Future<void> _showNotification(OrderNotificationEvent event) async {
    if (!_initialized) return;
    try {
      await _notifications.show(
        id: _notificationId++,
        title: event.title,
        body: event.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'order_updates',
            'Order updates',
            channelDescription:
                'Notifications about customer and seller order updates.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (error) {
      debugPrint('Could not show order notification: $error');
    }
  }

  void markOrdersOpened() {
    if (!_hasUnseenChanges) return;
    _hasUnseenChanges = false;
    notifyListeners();
  }

  Future<void> stop([String? uid]) async {
    if (uid != null && _activeUid != uid) return;
    _activeUid = null;
    _isSeller = null;
    _onEvent = null;
    _hasBaseline = false;
    _hasUnseenChanges = false;
    _previousStatuses = <String, OrderStatus>{};
    _previousOrders = <String, Order>{};
    final StreamSubscription<List<Order>>? subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }
}
