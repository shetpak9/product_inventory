import 'dart:async';

import 'package:app_links/app_links.dart';

class PaymentLink {
  const PaymentLink({required this.orderId, required this.result});

  final String orderId;
  final String result;
}

class PaymentLinkService {
  PaymentLinkService._();

  static final PaymentLinkService instance = PaymentLinkService._();

  final AppLinks _appLinks = AppLinks();
  final StreamController<PaymentLink> _controller =
      StreamController<PaymentLink>.broadcast();
  StreamSubscription<Uri>? _subscription;
  PaymentLink? _pending;

  Stream<PaymentLink> get links => _controller.stream;

  Future<void> initialize() async {
    if (_subscription != null) return;
    try {
      final Uri? initialLink = await _appLinks.getInitialLink();
      _handleUri(initialLink);
    } catch (_) {
      // A missing or unavailable initial link is not actionable.
    }
    _subscription = _appLinks.uriLinkStream.listen(_handleUri);
  }

  PaymentLink? takePending() {
    final PaymentLink? link = _pending;
    _pending = null;
    return link;
  }

  void _handleUri(Uri? uri) {
    final PaymentLink? link = _parse(uri);
    if (link == null) return;
    _pending = link;
    _controller.add(link);
  }

  PaymentLink? _parse(Uri? uri) {
    if (uri == null ||
        uri.scheme != 'alaspandesal' ||
        uri.host != 'payment-result') {
      return null;
    }
    final String orderId = uri.queryParameters['orderId'] ?? '';
    final String result = uri.queryParameters['result'] ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(orderId) ||
        (result != 'success' && result != 'cancel')) {
      return null;
    }
    return PaymentLink(orderId: orderId, result: result);
  }
}
