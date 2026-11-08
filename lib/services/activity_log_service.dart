import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:product_inventory/model/user.dart';

class ActivityLogService {
  ActivityLogService({FirebaseDatabase? database})
    : _database = database ?? _safeDatabaseInstance();

  static const String _databaseUrl =
      'https://product-inventory-29475-default-rtdb.firebaseio.com';

  final FirebaseDatabase? _database;

  static FirebaseDatabase? _safeDatabaseInstance() {
    try {
      return FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: _databaseUrl,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> logActivity({
    required String action,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? details,
  }) async {
    final User? user = FirebaseAuth.instance.currentUser;
    final FirebaseDatabase? database = _database;
    if (user == null || database == null) return;

    try {
      final DataSnapshot profileSnapshot = await database
          .ref('users/${user.uid}')
          .get()
          .timeout(const Duration(seconds: 10));
      final Object? rawProfile = profileSnapshot.value;
      final Map<dynamic, dynamic>? profile = rawProfile is Map
          ? rawProfile
          : null;
      final String role = UserRole.fromString(
        profile?['role']?.toString(),
      ).name;
      final String firstName = profile?['firstName']?.toString() ?? '';
      final String lastName = profile?['lastName']?.toString() ?? '';
      final String userName = '$firstName $lastName'.trim();
      final DatabaseReference logRef = database.ref('activity_logs').push();
      final Map<String, Object?> record = <String, Object?>{
        'userUid': user.uid,
        'userName': userName,
        'userRole': role,
        'action': action,
        'createdAt': ServerValue.timestamp,
      };
      if (entityType != null) record['entityType'] = entityType;
      if (entityId != null) record['entityId'] = entityId;
      if (details != null && details.isNotEmpty) {
        record['details'] = _safeDetails(details);
      }
      await logRef.set(record).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      debugPrint('[ACTIVITY] Activity log timed out for $action.');
    } on FirebaseException catch (error) {
      debugPrint('[ACTIVITY] Activity log failed: ${error.code}.');
    } catch (error) {
      debugPrint('[ACTIVITY] Activity log failed: $error');
    }
  }

  Map<String, dynamic> _safeDetails(Map<String, dynamic> details) {
    const Set<String> blockedKeys = <String>{
      'password',
      'token',
      'accessToken',
      'idToken',
      'secret',
      'secretKey',
      'paymentCredential',
      'cardNumber',
      'cvv',
    };
    return <String, dynamic>{
      for (final MapEntry<String, dynamic> entry in details.entries)
        if (!blockedKeys.contains(entry.key)) entry.key: entry.value,
    };
  }
}
