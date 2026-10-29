import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/screen/home/category_products_screen.dart';
import 'package:product_inventory/screen/home/product_grid_tile.dart';
import 'package:product_inventory/screen/home/store_screen.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/product_image.dart';

void _openStore(BuildContext context, Store store) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StoreScreen(storeId: store.ownerId),
    ),
  );
}

class Shop extends StatefulWidget {
  const Shop({super.key});

  @override
  State<Shop> createState() => _ShopState();
}

class _ShopState extends State<Shop> {
  late final Stream<List<Product>> _products = DatabaseService().products;
  late final Stream<List<Store>> _stores = DatabaseService().storesStream;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _categoriesFrom(List<Product> products) {
    final Set<String> found = products
        .map((Product p) => p.category.trim())
        .where((String c) => c.isNotEmpty)
        .toSet();
    final List<String> categories = <String>[
      ...(found.isEmpty ? ProductCategories.all : found),
    ]..sort();
    return categories;
  }

  String? _imageFor(List<Product> products, String category) {
    for (final Product p in products) {
      final String? url = p.imageUrl;
      if (p.category.trim().toLowerCase() == category.toLowerCase() &&
          url != null &&
          url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (String value) => setState(() => _query = value),
            decoration: InputDecoration(
              hintText: 'Search products or stores',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Product>>(
            stream: _products,
            builder: (
              BuildContext context,
              AsyncSnapshot<List<Product>> productsSnapshot,
            ) {
              if (productsSnapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Unable to load the shop: ${productsSnapshot.error}',
                    ),
                  ),
                );
              }
              if (!productsSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              return StreamBuilder<List<Store>>(
                stream: _stores,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<List<Store>> storesSnapshot,
                ) {
                  // If stores fail to load the shop still works without them.
                  return _buildContent(
                    productsSnapshot.data!,
                    storesSnapshot.data ?? <Store>[],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContent(List<Product> products, List<Store> stores) {
    final String query = _query.trim().toLowerCase();
    final List<Widget> slivers = <Widget>[];

    if (query.isEmpty) {
      if (stores.isNotEmpty) {
        slivers
          ..add(const SliverToBoxAdapter(child: _SectionTitle('Stores')))
          ..add(SliverToBoxAdapter(child: _StoreStrip(stores: stores)));
      }

      final List<String> categories = _categoriesFrom(products);
      slivers
        ..add(const SliverToBoxAdapter(child: _SectionTitle('Shop by Categories')))
        ..add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.94,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) {
                  final String category = categories[index];
                  return _CategoryCard(
                    category: category,
                    imageUrl: _imageFor(products, category),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CategoryProductsScreen(category: category),
                        ),
                      );
                    },
                  );
                },
                childCount: categories.length,
              ),
            ),
          ),
        );
    } else {
      final List<Store> matchingStores = stores
          .where((Store s) => s.name.toLowerCase().contains(query))
          .toList();
      final List<Product> matchingProducts = products
          .where(
            (Product p) =>
                p.name.toLowerCase().contains(query) ||
                p.category.toLowerCase().contains(query) ||
                p.storeName.toLowerCase().contains(query),
          )
          .toList();

      if (matchingStores.isEmpty && matchingProducts.isEmpty) {
        slivers.add(
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No results for "$_query".')),
          ),
        );
      } else {
        if (matchingStores.isNotEmpty) {
          slivers
            ..add(const SliverToBoxAdapter(child: _SectionTitle('Stores')))
            ..add(
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) =>
                      _StoreTile(store: matchingStores[index]),
                  childCount: matchingStores.length,
                ),
              ),
            );
        }
        if (matchingProducts.isNotEmpty) {
          slivers
            ..add(const SliverToBoxAdapter(child: _SectionTitle('Products')))
            ..add(
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                sliver: SliverGrid(
                  gridDelegate: kProductGridDelegate,
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) =>
                        ProductGridTile(product: matchingProducts[index]),
                    childCount: matchingProducts.length,
                  ),
                ),
              ),
            );
        }
      }
    }

    return CustomScrollView(slivers: slivers);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _StoreStrip extends StatelessWidget {
  const _StoreStrip({required this.stores});

  final List<Store> stores;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stores.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (BuildContext context, int index) {
          final Store store = stores[index];
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openStore(context, store),
            child: SizedBox(
              width: 76,
              child: Column(
                children: <Widget>[
                  ClipOval(
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: ProductImage(url: store.logoUrl, borderRadius: 0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    store.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!store.isOpen)
                    Text(
                      'Closed',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  const _StoreTile({required this.store});

  final Store store;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => _openStore(context, store),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: ProductImage(url: store.logoUrl, borderRadius: 24),
      ),
      title: Text(store.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(store.isOpen ? 'Open' : 'Closed'),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.imageUrl,
    required this.onTap,
  });

  final String category;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: ProductImage(url: imageUrl, borderRadius: 6)),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Text(
                category,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
