import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/home/cart.dart';
import 'package:product_inventory/screen/home/product_detail.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/favorites_store.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_thumb.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final FavoritesStore _favorites = FavoritesStore.instance;
  final DatabaseService _db = DatabaseService();
  late final Stream<List<Product>> _products = _db.products;

  bool _loading = true;
  String? _error;
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _favorites.load();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      debugPrint('Favorites load failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load your favorites. Please try again.';
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Disables the row's buttons while [action] runs.
  Future<void> _runBusy(
    String productId,
    Future<void> Function() action,
  ) async {
    if (!_busy.add(productId)) return;
    setState(() {});
    try {
      await action();
    } finally {
      _busy.remove(productId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _remove(Product product) {
    return _runBusy(product.id, () async {
      try {
        await _favorites.remove(product.id);
      } catch (error) {
        debugPrint('Favorite removal failed: $error');
        _snack('Could not remove this favorite.');
      }
    });
  }

  Future<void> _addToCart(Product product) {
    return _runBusy(product.id, () async {
      if (product.optionGroups.isNotEmpty) {
        _openProduct(product);
        return;
      }
      try {
        if (!await _db.isStoreOpen(product.sellerId)) {
          _snack('This store is closed right now.');
          return;
        }
        await CartStore.instance.addProduct(product);
        _snack('${product.name} added to cart.');
      } catch (error) {
        debugPrint('Favorite add-to-cart failed: $error');
        _snack('Could not add this item to your cart.');
      }
    });
  }

  void _openProduct(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Text(
            'Favorites',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: _favorites,
      builder: (BuildContext context, Widget? child) {
        return StreamBuilder<List<Product>>(
          stream: _products,
          builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Unable to load products: ${snapshot.error}'),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final List<Product> items = snapshot.data!
                .where((Product p) => _favorites.contains(p.id))
                .toList();
            if (items.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No favorites yet.\nTap the heart on a product to save it here.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final Product product = items[index];
                final bool busy = _busy.contains(product.id);
                final String subtitle = product.storeName.isEmpty
                    ? formatPeso(product.price)
                    : '${formatPeso(product.price)} · ${product.storeName}';

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  onTap: () => _openProduct(product),
                  leading: ProductThumb(url: product.imageUrl, size: 64),
                  title: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: SizedBox(
                    width: 104,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Add to cart',
                          onPressed: busy ? null : () => _addToCart(product),
                          icon: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_shopping_cart),
                        ),
                        IconButton(
                          tooltip: 'Remove from favorites',
                          onPressed: busy ? null : () => _remove(product),
                          icon: const Icon(
                            Icons.favorite,
                            color: AppColors.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
