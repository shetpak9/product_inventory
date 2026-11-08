import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/services/activity_log_service.dart';

/// Turns auth/database exceptions into messages that are safe to show.
String friendlyAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'weak-password':
        return 'Choose a stronger password (at least 6 characters).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'network-request-failed':
        return 'No internet connection. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}

class AuthService {
  AuthService({FirebaseAuth? auth, DatabaseService? database})
    : _auth = auth ?? _safeAuthInstance(),
      _injectedDatabase = database;

  static FirebaseAuth? _safeAuthInstance() {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  final FirebaseAuth? _auth;
  final DatabaseService? _injectedDatabase;
  final ActivityLogService _activityLog = ActivityLogService();
  late final DatabaseService _database = _injectedDatabase ?? DatabaseService();

  UserId? _userFromFirebaseUser(User? user) {
    return user != null ? UserId(uid: user.uid) : null;
  }

  UserId? get currentUser => _userFromFirebaseUser(_auth?.currentUser);
  User? get currentFirebaseUser => _auth?.currentUser;

  Stream<UserId?> get userStream {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      return const Stream<UserId?>.empty();
    }
    return auth.authStateChanges().map(_userFromFirebaseUser);
  }

  Future<UserId?> signIn(String email, String password) async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      throw StateError('Firebase is not available in this environment.');
    }

    final UserCredential result = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    final UserId? signedInUser = _userFromFirebaseUser(result.user);
    if (signedInUser != null) {
      unawaited(
        _activityLog.logActivity(
          action: 'auth.login',
          entityType: 'user',
          entityId: signedInUser.uid,
        ),
      );
    }
    return signedInUser;
  }

  /// Creates the auth user AND the profile (with role). If the profile write
  /// fails, the auth user is deleted so the person can simply try again.
  Future<UserId> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required UserRole role,
  }) async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      throw StateError('Firebase is not available in this environment.');
    }

    final UserCredential credential = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password.trim(),
    );
    final User? user = credential.user;
    if (user == null) {
      throw StateError('Firebase did not return a user.');
    }

    try {
      await _database.createUserProfile(
        UserData(
          uid: user.uid,
          firstName: firstName.trim(),
          lastName: lastName.trim(),
          role: role,
        ),
      );
    } catch (e) {
      debugPrint('Profile write failed, rolling back auth user: $e');
      try {
        await user.delete();
      } catch (_) {
        await auth.signOut();
      }
      rethrow;
    }
    unawaited(
      _activityLog.logActivity(
        action: 'auth.registered',
        entityType: 'user',
        entityId: user.uid,
      ),
    );
    return UserId(uid: user.uid);
  }

  Future<void> signOut() async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      return;
    }
    unawaited(_activityLog.logActivity(action: 'auth.logout'));
    await auth.signOut();
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final FirebaseAuth? auth = _auth;
    if (auth == null) {
      throw StateError('Firebase is not available in this environment.');
    }
    await auth.sendPasswordResetEmail(email: email.trim());
    unawaited(
      _activityLog.logActivity(action: 'auth.password_reset_requested'),
    );
  }

  Future<void> reauthenticate(String password) async {
    final FirebaseAuth? auth = _auth;
    final User? user = auth?.currentUser;
    if (user == null || user.email == null) {
      throw StateError('A signed-in email account is required.');
    }
    final AuthCredential credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
  }

  Future<void> deleteCurrentUser() async {
    final User? user = _auth?.currentUser;
    if (user == null) {
      throw StateError('No signed-in user was found.');
    }
    await user.delete();
  }
}
