import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class PaymentService {
  PaymentService({http.Client? client}) : _client = client ?? http.Client();

  static const String _configuredBaseUrl = String.fromEnvironment(
    'PAYMENTS_BASE_URL',
  );
  final http.Client _client;

  String get _baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl;
    }
    if (kIsWeb) {
      return 'http://127.0.0.1:5001/product-inventory-29475/us-central1';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001/product-inventory-29475/us-central1';
    }
    return 'http://127.0.0.1:5001/product-inventory-29475/us-central1';
  }

  Future<String> createCheckout(String orderId) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required to start payment.');
    }
    final String token = await user.getIdToken() ?? '';
    if (token.isEmpty) {
      throw StateError('Could not refresh the sign-in token.');
    }
    final http.Response response = await _client.post(
      Uri.parse('$_baseUrl/createPaymongoCheckout'),
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, String>{'orderId': orderId}),
    );
    final dynamic decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final String message = decoded is Map && decoded['error'] is String
          ? decoded['error'] as String
          : 'Unable to start PayMongo checkout.';
      throw StateError(message);
    }
    final String? url = decoded is Map && decoded['checkoutUrl'] is String
        ? decoded['checkoutUrl'] as String
        : null;
    if (url == null || !url.startsWith('https://')) {
      throw StateError('PayMongo returned an invalid checkout URL.');
    }
    return url;
  }

  Future<bool> openCheckout(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
