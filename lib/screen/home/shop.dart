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
  String? _categoryFilter;
  String? _sellerFilter;
  _AvailabilityFilter _availabilityFilter = _AvailabilityFilter.all;
  _PriceSort _priceSort = _PriceSort.none;

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
            builder:
                (
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
                    builder:
                        (
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
    final List<String> categories = _categoriesFrom(products);
    final List<Product> filteredProducts = products.where((Product product) {
      final bool matchesQuery =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query) ||
          product.storeName.toLowerCase().contains(query);
      final bool matchesCategory =
          _categoryFilter == null ||
          product.category.trim().toLowerCase() ==
              _categoryFilter!.toLowerCase();
      final bool matchesSeller =
          _sellerFilter == null || product.sellerId == _sellerFilter;
      final bool outOfStock =
          product.stockQuantity != null && product.stockQuantity == 0;
      final bool matchesAvailability =
          _availabilityFilter == _AvailabilityFilter.all ||
          (_availabilityFilter == _AvailabilityFilter.available &&
              !outOfStock) ||
          (_availabilityFilter == _AvailabilityFilter.outOfStock && outOfStock);
      return matchesQuery &&
          matchesCategory &&
          matchesSeller &&
          matchesAvailability;
    }).toList();
    if (_priceSort != _PriceSort.none) {
      filteredProducts.sort(
        (Product a, Product b) => _priceSort == _PriceSort.lowToHigh
            ? a.price.compareTo(b.price)
            : b.price.compareTo(a.price),
      );
    }
    final List<Widget> slivers = <Widget>[];
    slivers.add(
      SliverToBoxAdapter(
        child: _FilterBar(
          category: _categoryFilter,
          categories: categories,
          sellerId: _sellerFilter,
          stores: stores,
          availability: _availabilityFilter,
          priceSort: _priceSort,
          onCategoryChanged: (String? value) =>
              setState(() => _categoryFilter = value),
          onSellerChanged: (String? value) =>
              setState(() => _sellerFilter = value),
          onAvailabilityChanged: (_AvailabilityFilter value) =>
              setState(() => _availabilityFilter = value),
          onPriceSortChanged: (_PriceSort value) =>
              setState(() => _priceSort = value),
          onClear: _clearFilters,
          hasFilters: _hasFilters,
        ),
      ),
    );

    if (query.isEmpty && !_hasFilters) {
      if (stores.isNotEmpty) {
        slivers
          ..add(const SliverToBoxAdapter(child: _SectionTitle('Stores')))
          ..add(SliverToBoxAdapter(child: _StoreStrip(stores: stores)));
      }

      slivers
        ..add(
          const SliverToBoxAdapter(child: _SectionTitle('Shop by Categories')),
        )
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
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
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
              }, childCount: categories.length),
            ),
          ),
        );
    } else {
      final List<Store> matchingStores = query.isEmpty
          ? <Store>[]
          : stores
                .where((Store s) => s.name.toLowerCase().contains(query))
                .toList();
      final List<Product> matchingProducts = filteredProducts;

      if (matchingStores.isEmpty && matchingProducts.isEmpty) {
        slivers.add(
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                query.isEmpty
                    ? 'No products match these filters.'
                    : 'No results for "$_query".',
              ),
            ),
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

  bool get _hasFilters =>
      _categoryFilter != null ||
      _sellerFilter != null ||
      _availabilityFilter != _AvailabilityFilter.all ||
      _priceSort != _PriceSort.none;

  void _clearFilters() {
    setState(() {
      _categoryFilter = null;
      _sellerFilter = null;
      _availabilityFilter = _AvailabilityFilter.all;
      _priceSort = _PriceSort.none;
    });
  }
}

enum _AvailabilityFilter { all, available, outOfStock }

enum _PriceSort { none, lowToHigh, highToLow }

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.category,
    required this.categories,
    required this.sellerId,
    required this.stores,
    required this.availability,
    required this.priceSort,
    required this.onCategoryChanged,
    required this.onSellerChanged,
    required this.onAvailabilityChanged,
    required this.onPriceSortChanged,
    required this.onClear,
    required this.hasFilters,
  });

  final String? category;
  final List<String> categories;
  final String? sellerId;
  final List<Store> stores;
  final _AvailabilityFilter availability;
  final _PriceSort priceSort;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onSellerChanged;
  final ValueChanged<_AvailabilityFilter> onAvailabilityChanged;
  final ValueChanged<_PriceSort> onPriceSortChanged;
  final VoidCallback onClear;
  final bool hasFilters;

  @override
  Widget build(BuildContext context) {
    final List<Store> availableStores = stores;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: <Widget>[
          DropdownButton<String?>(
            value: category,
            hint: const Text('Category'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All categories'),
              ),
              ...categories.map(
                (String value) =>
                    DropdownMenuItem<String?>(value: value, child: Text(value)),
              ),
            ],
            onChanged: onCategoryChanged,
          ),
          const SizedBox(width: 12),
          DropdownButton<String?>(
            value: sellerId,
            hint: const Text('Seller'),
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All sellers'),
              ),
              ...availableStores.map(
                (Store store) => DropdownMenuItem<String?>(
                  value: store.ownerId,
                  child: Text(store.name),
                ),
              ),
            ],
            onChanged: onSellerChanged,
          ),
          const SizedBox(width: 12),
          DropdownButton<_AvailabilityFilter>(
            value: availability,
            items: const <DropdownMenuItem<_AvailabilityFilter>>[
              DropdownMenuItem(
                value: _AvailabilityFilter.all,
                child: Text('All stock'),
              ),
              DropdownMenuItem(
                value: _AvailabilityFilter.available,
                child: Text('In stock'),
              ),
              DropdownMenuItem(
                value: _AvailabilityFilter.outOfStock,
                child: Text('Out of stock'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onAvailabilityChanged(value);
            },
          ),
          const SizedBox(width: 12),
          DropdownButton<_PriceSort>(
            value: priceSort,
            items: const <DropdownMenuItem<_PriceSort>>[
              DropdownMenuItem(value: _PriceSort.none, child: Text('Sort by')),
              DropdownMenuItem(
                value: _PriceSort.lowToHigh,
                child: Text('Price: low to high'),
              ),
              DropdownMenuItem(
                value: _PriceSort.highToLow,
                child: Text('Price: high to low'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onPriceSortChanged(value);
            },
          ),
          if (hasFilters)
            TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    );
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
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade700,
                      ),
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
