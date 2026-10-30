import 'package:flutter/material.dart';
import 'package:product_inventory/screen/home/my_orders.dart';
import 'package:product_inventory/shared/app_theme.dart';

class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({
    super.key,
    required this.orderCount,
    required this.total,
    this.paymentConfirmed = false,
  });

  final int orderCount;
  final double total;
  final bool paymentConfirmed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (paymentConfirmed) ...<Widget>[
                  const Icon(Icons.check_circle_outline, size: 64),
                  const SizedBox(height: 20),
                ],
                Text(
                  paymentConfirmed
                      ? 'Thank you for shopping with us!'
                      : 'Your order has been placed.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  paymentConfirmed
                      ? 'Your payment has been confirmed.'
                      : 'Your order has been recorded. No payment was processed in the app.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  '$orderCount ${orderCount == 1 ? 'order' : 'orders'} placed',
                ),
                const SizedBox(height: 8),
                Text('Order total: ${formatPeso(total)}'),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const MyOrdersScreen(),
                      ),
                    ),
                    child: const Text('View my orders'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
