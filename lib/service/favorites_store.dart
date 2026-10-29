import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:product_inventory/service/database.dart';

/// Product ids the signed-in customer has marked as favorites.
///
/// Only ids are stored. Names, prices and photos always come from the live
/// product list, so they never go stale and deleted products drop out.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._() {
    FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  static final FavoritesStore instance = FavoritesStore._();

  final Set<String> _ids = <String>{};
  final DatabaseService _database = DatabaseService();
  String? _uid;
  bool _loaded = false;

  bool contains(String productId) => _ids.contains(productId);

  void _onAuthChanged(User? user) {
    if (user?.uid != _uid) {
      _ids.clear();
      _uid = null;
      _loaded = false;
      notifyListeners();
    }
  }

  /// Safe to call many times; only the first call per user hits the database.
  Future<void> load() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _onAuthChanged(null);
      return;
    }
    if (_loaded && _uid == uid) {
      return;
    }

    // No notifyListeners() here: load() is often called from initState.
    _ids.clear();
    _uid = uid;
    _loaded = false;

    final Set<String> fetched = await _database.getFavoriteIds(uid);
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      return;
    }

    _ids
      ..clear()
      ..addAll(fetched);
    _loaded = true;
    notifyListeners();
  }

  Future<void> add(String productId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('A signed-in user is required to use favorites.');
    }
    if (_ids.contains(productId)) return;

    await _database.addFavorite(uid, productId);
    _ids.add(productId);
    notifyListeners();
  }

  Future<void> remove(String productId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await _database.removeFavorite(uid, productId);
    _ids.remove(productId);
    notifyListeners();
  }

  /// Heart button behaviour: add if missing, remove if present.
  Future<void> toggle(String productId) async {
    await load();
    if (contains(productId)) {
      await remove(productId);
    } else {
      await add(productId);
    }
  }
}
