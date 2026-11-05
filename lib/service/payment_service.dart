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

  Future<({double discountAmount, double finalTotal})> applyDiscount(
    String orderId,
    String code,
  ) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required to apply a discount.');
    }

    // ignore: unused_element
    Future<void> nestedPublishPromotionNotifications({
      required String promotionId,
      required String code,
    }) async {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('A signed-in seller is required.');
      }
      final String token =
          await user.getIdToken(true).timeout(const Duration(seconds: 15)) ??
          '';
      final http.Response response = await _client
          .post(
            Uri.parse('$_baseUrl/api/promotions/notify'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'promotionId': promotionId,
              'code': code,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('Promotion notifications could not be sent.');
      }
    }

    try {
      final String token =
          await user.getIdToken(true).timeout(const Duration(seconds: 15)) ??
          '';
      final http.Response response = await _client
          .post(
            Uri.parse('$_baseUrl/api/payments/apply-discount'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{
              'orderId': orderId,
              'code': code,
            }),
          )
          .timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        decoded = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          decoded is Map && decoded['error'] is String
              ? decoded['error'] as String
              : 'Unable to apply this discount code.',
        );
      }
      if (decoded is! Map ||
          decoded['discountAmount'] is! num ||
          decoded['finalTotal'] is! num) {
        throw StateError('The payment service returned an invalid discount.');
      }
      return (
        discountAmount: (decoded['discountAmount'] as num).toDouble(),
        finalTotal: (decoded['finalTotal'] as num).toDouble(),
      );
    } on TimeoutException {
      throw StateError('Discount validation took too long. Please try again.');
    } on SocketException {
      throw StateError('Could not connect to validate the discount.');
    } on FirebaseAuthException {
      throw StateError(
        'Your sign-in session has expired. Please sign in again.',
      );
    }
  }

  Future<void> publishPromotionNotifications({
    required String promotionId,
    required String code,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('A signed-in seller is required.');
    final String token =
        await user.getIdToken(true).timeout(const Duration(seconds: 15)) ?? '';
    final http.Response response = await _client
        .post(
          Uri.parse('$_baseUrl/api/promotions/notify'),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'promotionId': promotionId,
            'code': code,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Promotion notifications could not be sent.');
    }
  }

  Future<String> createCheckout(String orderId) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required to start payment.');
    }
    String token;
    try {
      debugPrint('[CHECKOUT] Firebase ID token refresh started');
      token =
          await user.getIdToken(true).timeout(const Duration(seconds: 15)) ??
          '';
    } on TimeoutException {
      debugPrint('[CHECKOUT] Firebase ID token refresh timed out');
      throw StateError(
        'Firebase sign-in verification took too long. Check your connection and try again.',
      );
    }
    try {
      if (token.isEmpty) {
        throw StateError(
          'Your sign-in session has expired. Please sign in again.',
        );
      }
      debugPrint('[CHECKOUT] Firebase ID token acquired');
      final Uri checkoutUri = Uri.parse('$_baseUrl/api/payments/checkout');
      debugPrint(
        '[CHECKOUT] Request started: ${checkoutUri.host}:${checkoutUri.port}',
      );
      final http.Response response = await _client
          .post(
            checkoutUri,
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, String>{'orderId': orderId}),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint('[CHECKOUT] Response received: HTTP ${response.statusCode}');
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
          message =
              'Unable to start PayMongo checkout (HTTP ${response.statusCode}).';
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
      debugPrint('[CHECKOUT] Backend checkout request timed out');
      throw StateError(
        'The payment service took too long to respond. Check your connection and try again.',
      );
    } on SocketException {
      debugPrint('[CHECKOUT] Connection failed');
      throw StateError(
        'Could not connect to the payment service. Make sure the backend is running.',
      );
    } on http.ClientException {
      throw StateError('Could not connect to the payment service. Try again.');
    } on FirebaseAuthException catch (error) {
      debugPrint('Could not refresh Firebase ID token: ${error.code}');
      throw StateError(
        'Your sign-in session has expired. Please sign in again.',
      );
    }
  }

  Future<String> verifyPayment(String orderId) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('A signed-in user is required to verify payment.');
    }
    try {
      final String token =
          await user.getIdToken(true).timeout(const Duration(seconds: 15)) ??
          '';
      final http.Response response = await _client
          .post(
            Uri.parse('$_baseUrl/api/payments/verify'),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
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
        throw StateError(
          decoded is Map && decoded['error'] is String
              ? decoded['error'] as String
              : 'Payment verification failed.',
        );
      }
      if (decoded is! Map || decoded['paymentStatus'] is! String) {
        throw StateError('Payment verification returned an invalid response.');
      }
      return decoded['paymentStatus'] as String;
    } on TimeoutException {
      throw StateError('Payment verification took too long. Please try again.');
    } on SocketException {
      throw StateError('Could not connect to verify payment.');
    } on FirebaseAuthException {
      throw StateError(
        'Your sign-in session has expired. Please sign in again.',
      );
    }
  }

  Future<bool> openCheckout(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
