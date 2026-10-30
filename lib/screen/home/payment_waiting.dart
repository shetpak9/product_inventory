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
  });

  final String orderId;
  final String? checkoutUrl;

  @override
  State<PaymentWaitingScreen> createState() => _PaymentWaitingScreenState();
}

class _PaymentWaitingScreenState extends State<PaymentWaitingScreen> {
  final DatabaseService _database = DatabaseService();
  final PaymentService _payments = PaymentService();
  StreamSubscription<Order?>? _subscription;
  Timer? _timeoutTimer;
  Order? _order;
  Object? _streamError;
  bool _receivedEvent = false;
  bool _timedOut = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _subscription = _database
        .orderStream(widget.orderId)
        .listen(_handleOrder, onError: _handleError);
    _timeoutTimer = Timer(const Duration(minutes: 3), () {
      if (!mounted) return;
      setState(() => _timedOut = true);
    });
  }

  void _handleOrder(Order? order) {
    if (!mounted) return;
    setState(() {
      _order = order;
      _streamError = null;
      _receivedEvent = true;
    });
    if (order?.paymentStatus == 'paid' &&
        order?.status != OrderStatus.cancelled) {
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

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _reopenPaymentPage() async {
    final String? url = widget.checkoutUrl;
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

  void _retry() {
    setState(() {
      _streamError = null;
      _order = null;
      _receivedEvent = false;
    });
    _subscription?.cancel();
    _subscription = _database
        .orderStream(widget.orderId)
        .listen(_handleOrder, onError: _handleError);
  }

  @override
  Widget build(BuildContext context) {
    final Order? order = _order;
    final Widget body;
    if (_streamError != null) {
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
        'Payment failed.',
        'Your PayMongo payment was not completed.',
        'Back to my orders',
        _backToOrders,
      );
    } else if (_timedOut) {
      body = _messageState(
        Icons.hourglass_empty,
        "We haven't received your payment confirmation yet.",
        'If you paid, it will update in My Orders shortly.',
        'View my orders',
        _backToOrders,
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
            if (widget.checkoutUrl?.isNotEmpty == true) ...<Widget>[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _reopenPaymentPage,
                child: const Text('Reopen payment page'),
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
}
