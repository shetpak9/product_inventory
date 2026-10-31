import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    if (_configuredBaseUrl.isNotEmpty) return _configuredBaseUrl;
    if (kIsWeb) return 'http://127.0.0.1:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://127.0.0.1:3000';
  }

  Future<String> createCheckout(String orderId) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required to start payment.');
    }
    try {
      final String token = await user.getIdToken(true) ?? '';
      if (token.isEmpty) {
        throw StateError(
          'Your sign-in session has expired. Please sign in again.',
        );
      }
      final http.Response response = await _client
          .post(
            Uri.parse('$_baseUrl/api/payments/checkout'),
            headers: <String, String>{
              'Authorization': String.fromCharCodes(<int>[
                    66,
                    101,
                    97,
                    114,
                    101,
                    114,
                    32,
                  ]) +
                  token,
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{'orderId': orderId}),
          )
          .timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String message;
        if (response.statusCode == 401) {
          message = 'Your sign-in session has expired. Please sign in again.';
        } else if (response.statusCode >= 500) {
          message = 'The payment service is temporarily unavailable.';
        } else if (decoded is Map && decoded['error'] is String) {
          message = decoded['error'] as String;
        } else {
          message = 'Unable to start PayMongo checkout.';
        }
        throw StateError(message);
      }
      final String? url = decoded is Map && decoded['checkoutUrl'] is String
          ? decoded['checkoutUrl'] as String
          : null;
      if (url == null || !url.startsWith('https://')) {
        throw StateError('PayMongo returned an invalid checkout URL.');
      }
      return url;
    } on TimeoutException {
      throw StateError(
        'The payment service took too long to respond. Check your connection and try again.',
      );
    } on SocketException {
      throw StateError(
        'Could not connect to the payment service. Make sure the backend is running.',
      );
    } on http.ClientException {
      throw StateError('Could not connect to the payment service. Try again.');
    } on FirebaseAuthException catch (error) {
      debugPrint('Could not refresh Firebase ID token: ${error.code}');
      throw StateError('Your sign-in session has expired. Please sign in again.');
    }
  }

  Future<bool> openCheckout(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
