import 'dart:async';

import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/screen/home/my_orders.dart';
import 'package:product_inventory/screen/home/order_confirmation.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/payment_service.dart';

class PaymentWaitingScreen extends StatefulWidget {
  const PaymentWaitingScreen({
    super.key,
    required this.orderId,
    this.checkoutUrl,
    this.result = 'success',
  });

  final String orderId;
  final String? checkoutUrl;
  final String result;

  static final Set<String> _activeOrderIds = <String>{};

  static bool isActiveFor(String orderId) => _activeOrderIds.contains(orderId);

  @override
  State<PaymentWaitingScreen> createState() => _PaymentWaitingScreenState();
}

class _PaymentWaitingScreenState extends State<PaymentWaitingScreen>
    with WidgetsBindingObserver {
  final DatabaseService _database = DatabaseService();
  final PaymentService _payments = PaymentService();
  StreamSubscription<Order?>? _subscription;
  Timer? _timeoutTimer;
  Timer? _verificationTimer;
  Order? _order;
  Object? _streamError;
  bool _receivedEvent = false;
  bool _timedOut = false;
  bool _navigating = false;
  bool _refreshing = false;
  bool _checkoutBusy = false;
  bool _verificationInFlight = false;
  int _verificationAttempts = 0;
  bool _verificationExhausted = false;
  late String? _checkoutUrl = widget.checkoutUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PaymentWaitingScreen._activeOrderIds.add(widget.orderId);
    _subscription = _database
        .orderStream(widget.orderId)
        .listen(_handleOrder, onError: _handleError);
    if (widget.result == 'cancel') {
      _verificationExhausted = true;
    } else {
      _startTimeout();
      _startVerification();
    }
    unawaited(_refreshOrder());
  }

  void _startVerification() {
    _verificationTimer?.cancel();
    _verificationAttempts = 0;
    _verificationExhausted = false;
    unawaited(_verifyPayment());
    _verificationTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_verifyPayment()),
    );
  }

  Future<void> _verifyPayment() async {
    if (!mounted ||
        widget.result == 'cancel' ||
        _verificationExhausted ||
        _verificationInFlight ||
        _order?.paymentStatus == 'paid') {
      return;
    }
    if (_verificationAttempts >= 10) {
      _verificationExhausted = true;
      _verificationTimer?.cancel();
      _timeoutTimer?.cancel();
      if (mounted) setState(() => _timedOut = true);
      return;
    }
    _verificationAttempts++;
    _verificationInFlight = true;
    try {
      debugPrint(
        '[VERIFY] Attempt $_verificationAttempts/10 for ${widget.orderId}',
      );
      final String status = await _payments.verifyPayment(widget.orderId);
      if (status == 'paid') await _refreshOrder();
    } catch (error) {
      debugPrint('[VERIFY] Payment verification attempt failed: $error');
    } finally {
      _verificationInFlight = false;
    }
  }

  void _handleOrder(Order? order) {
    if (!mounted) return;
    debugPrint(
      '[PAYMENT] Order ${widget.orderId} payment status: '
      '${order?.paymentStatus ?? 'missing'}',
    );
    setState(() {
      _order = order;
      _streamError = null;
      _receivedEvent = true;
    });
    if (order?.paymentStatus == 'paid' &&
        order?.status != OrderStatus.cancelled) {
      _verificationTimer?.cancel();
      _timeoutTimer?.cancel();
      _showConfirmation(order!);
    }
  }

  void _handleError(Object error) {
    if (!mounted) return;
    setState(() => _streamError = error);
  }

  void _showConfirmation(Order order) {
    if (_navigating || !mounted) return;
    _navigating = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderConfirmationScreen(
            orderCount: 1,
            total: order.total,
            paymentConfirmed: true,
          ),
        ),
      );
    });
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(const Duration(minutes: 3), () {
      if (!mounted || _navigating) return;
      setState(() => _timedOut = true);
    });
  }

  Future<void> _refreshOrder() async {
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    try {
      final Order? order = await _database.getOrder(widget.orderId);
      if (mounted) _handleOrder(order);
    } catch (error) {
      debugPrint('[PAYMENT] Order refresh failed: $error');
      if (mounted) setState(() => _streamError = error);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[PAYMENT] App resumed; refreshing order ${widget.orderId}');
      _startTimeout();
      unawaited(_refreshOrder());
      if (widget.result != 'cancel') unawaited(_verifyPayment());
    }
  }

  Future<void> _reopenPaymentPage() async {
    final String? url = _checkoutUrl;
    if (url == null || url.isEmpty) return;
    try {
      final bool opened = await _payments.openCheckout(url);
      if (!opened) throw StateError('Could not open the payment page.');
    } catch (error) {
      debugPrint('Could not reopen PayMongo checkout: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the payment page: $error')),
      );
    }
  }

  Future<void> _startOrRetryPayment() async {
    if (_checkoutBusy || !mounted) return;
    setState(() => _checkoutBusy = true);
    try {
      final String url = await _payments.createCheckout(widget.orderId);
      if (!mounted) return;
      setState(() {
        _checkoutUrl = url;
        _timedOut = false;
      });
      final bool opened = await _payments.openCheckout(url);
      if (!opened) throw StateError('Could not open the payment page.');
    } catch (error) {
      debugPrint('Could not start PayMongo checkout: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start payment: $error')),
      );
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  void _retry() {
    setState(() {
      _streamError = null;
      _order = null;
      _receivedEvent = false;
      _timedOut = false;
    });
    _startTimeout();
    _startVerification();
    _subscription?.cancel();
    _subscription = _database
        .orderStream(widget.orderId)
        .listen(_handleOrder, onError: _handleError);
  }

  @override
  Widget build(BuildContext context) {
    final Order? order = _order;
    final Widget body;
    if (widget.result == 'cancel') {
      body = _messageState(
        Icons.cancel_outlined,
        'Payment cancelled.',
        'Your order remains unpaid. You can try paying again from My Orders.',
        'Back to my orders',
        _backToOrders,
      );
    } else if (_streamError != null) {
      body = _errorState('Unable to load your order.', _retry);
    } else if (!_receivedEvent) {
      body = const Center(child: CircularProgressIndicator());
    } else if (order == null) {
      body = _errorState('This order is no longer available.', _retry);
    } else if (order.status == OrderStatus.cancelled) {
      body = _messageState(
        Icons.cancel_outlined,
        'This order was cancelled.',
        'The payment cannot be confirmed for a cancelled order.',
        'Back to my orders',
        _backToOrders,
      );
    } else if (order.paymentStatus == 'failed') {
      body = _messageState(
        Icons.error_outline,
        'Payment failed or expired.',
        'Your order is still available. You can try the payment again.',
        'Retry payment',
        _startOrRetryPayment,
      );
    } else if (_timedOut) {
      body = _messageState(
        Icons.hourglass_empty,
        "We haven't received your payment confirmation yet.",
        'Check your orders in a moment.',
        'Go to order',
        _goToOrder,
      );
    } else {
      body = _waitingState();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SafeArea(child: body),
    );
  }

  Widget _waitingState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            const Text(
              'Waiting for payment confirmation...',
              textAlign: TextAlign.center,
            ),
            if (_checkoutUrl?.isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _reopenPaymentPage,
                child: const Text('Reopen payment page'),
              ),
            ],
            if (_checkoutUrl == null || _checkoutUrl!.isEmpty) ...<Widget>[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _checkoutBusy ? null : _startOrRetryPayment,
                child: _checkoutBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Start payment'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _messageState(
    IconData icon,
    String title,
    String message,
    String buttonLabel,
    VoidCallback onPressed,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 64),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }

  Widget _errorState(String message, VoidCallback onRetry) {
    return _messageState(
      Icons.cloud_off,
      message,
      'Please try again.',
      'Retry',
      onRetry,
    );
  }

  void _backToOrders() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const MyOrdersScreen()),
    );
  }

  void _goToOrder() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => CustomerOrderDetailScreen(orderId: widget.orderId),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PaymentWaitingScreen._activeOrderIds.remove(widget.orderId);
    _timeoutTimer?.cancel();
    _verificationTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
