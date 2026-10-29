import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/screen/home/product_grid_tile.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/product_image.dart';

/// What a customer sees when they visit a seller's store.
class StoreScreen extends StatefulWidget {
  const StoreScreen({super.key, required this.storeId});

  /// The seller's uid (the key under `stores/`).
  final String storeId;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  final DatabaseService _db = DatabaseService();
  late final Stream<Store?> _storeStream = _db.storeStream(widget.storeId);
  late final Stream<List<Product>> _productsStream =
      _db.sellerProductsStream(widget.storeId);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Store')),
      body: StreamBuilder<Store?>(
        stream: _storeStream,
        builder: (BuildContext context, AsyncSnapshot<Store?> storeSnapshot) {
          if (storeSnapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load this store: ${storeSnapshot.error}'),
              ),
            );
          }
          if (storeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final Store? store = storeSnapshot.data;
          if (store == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This store is no longer available.'),
              ),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _StoreHeader(store: store),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Text(
                  'Products',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: _buildProducts()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildProducts() {
    return StreamBuilder<List<Product>>(
      stream: _productsStream,
      builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Unable to load products: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<Product> products = snapshot.data!
            .where((Product p) => p.isAvailable)
            .toList();
        if (products.isEmpty) {
          return const Center(child: Text('No products available right now.'));
        }
        return ProductGrid(products: products);
      },
    );
  }
}

class _StoreHeader extends StatelessWidget {
  const _StoreHeader({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    final String description = store.description.trim();
    final String address = store.address.trim();
    final String phone = store.phone.trim();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 72,
                height: 72,
                child: ProductImage(url: store.logoUrl, borderRadius: 12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      store.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Chip(
                      label: Text(store.isOpen ? 'Open' : 'Closed'),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: store.isOpen
                          ? Colors.green.shade100
                          : Colors.red.shade100,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text(description, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          if (address.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(address)),
              ],
            ),
          ],
          if (phone.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                const Icon(Icons.phone_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(phone)),
              ],
            ),
          ],
          if (!store.isOpen) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              'This store is closed right now. You can browse, but ordering is paused.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
