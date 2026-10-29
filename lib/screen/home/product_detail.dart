import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/screen/home/cart.dart';
import 'package:product_inventory/screen/home/store_screen.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/favorites_store.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_image.dart';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Product product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final FavoritesStore _favorites = FavoritesStore.instance;
  final DatabaseService _db = DatabaseService();

  // Older products have no seller, so there is no store to watch.
  late final Stream<Store?>? _storeStream = widget.product.sellerId.isEmpty
      ? null
      : _db.storeStream(widget.product.sellerId);

  bool _addingToCart = false;
  bool _favoritesReady = false;
  bool _updatingFavorite = false;
  final Map<String, Object?> _selectedOptions = <String, Object?>{};
  final Map<String, TextEditingController> _optionTextControllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final ProductOptionGroup group in widget.product.optionGroups) {
      if (group.type == ProductOptionType.freeText) {
        _optionTextControllers[group.name] = TextEditingController();
      }
    }
    _prepareFavorites();
  }

  @override
  void dispose() {
    for (final TextEditingController controller
        in _optionTextControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _prepareFavorites() async {
    try {
      await _favorites.load();
    } catch (error) {
      debugPrint('Favorites load failed: $error');
    }
    if (mounted) {
      setState(() => _favoritesReady = true);
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openStore() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => StoreScreen(storeId: widget.product.sellerId),
      ),
    );
  }

  Future<void> _addToCart() async {
    if (_addingToCart) return;

    for (final ProductOptionGroup group in widget.product.optionGroups) {
      final Object? selected = group.type == ProductOptionType.freeText
          ? _optionTextControllers[group.name]?.text.trim()
          : _selectedOptions[group.name];
      final bool isEmpty =
          selected == null ||
          selected == '' ||
          (selected is List && selected.isEmpty);
      if (group.required && isEmpty) {
        _snack('Please complete ${group.name}.');
        return;
      }
    }

    setState(() => _addingToCart = true);
    try {
      if (!await _db.isStoreOpen(widget.product.sellerId)) {
        _snack('This store is closed right now.');
        return;
      }
      final Map<String, Object?> selections = <String, Object?>{
        ..._selectedOptions,
      };
      for (final ProductOptionGroup group in widget.product.optionGroups) {
        if (group.type == ProductOptionType.freeText) {
          final String text =
              _optionTextControllers[group.name]?.text.trim() ?? '';
          if (text.isNotEmpty) selections[group.name] = text;
        }
      }
      final double priceAdjustment = widget.product.optionGroups
          .where(
            (ProductOptionGroup group) =>
                group.type == ProductOptionType.singleChoice,
          )
          .fold<double>(0, (double total, ProductOptionGroup group) {
            final String? choice = selections[group.name] as String?;
            if (choice == null) return total;
            return total +
                group.choices
                    .where((ProductOptionChoice item) => item.label == choice)
                    .fold<double>(
                      0,
                      (double sum, ProductOptionChoice item) =>
                          sum + item.priceAdjustment,
                    );
          });
      await CartStore.instance.addProduct(
        widget.product,
        selectedOptions: selections,
        priceAdjustment: priceAdjustment,
      );
      _snack('${widget.product.name} added to cart.');
    } catch (error) {
      debugPrint('Add to cart failed: $error');
      _snack('Could not add this product to your cart. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _addingToCart = false);
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (_updatingFavorite) return;

    setState(() => _updatingFavorite = true);
    try {
      await _favorites.toggle(widget.product.id);
      _snack(
        _favorites.contains(widget.product.id)
            ? 'Added to your favorites.'
            : 'Removed from your favorites.',
      );
    } catch (error) {
      debugPrint('Favorite update failed: $error');
      _snack('Could not update your favorites. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _updatingFavorite = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Stream<Store?>? storeStream = _storeStream;
    final String title = widget.product.name.trim().isEmpty
        ? 'Product details'
        : widget.product.name.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: storeStream == null
          ? _buildBody(context, null)
          : StreamBuilder<Store?>(
              stream: storeStream,
              builder: (BuildContext context, AsyncSnapshot<Store?> snapshot) {
                return _buildBody(context, snapshot.data);
              },
            ),
    );
  }

  Widget _buildBody(BuildContext context, Store? store) {
    final Product product = widget.product;
    final String category = product.category.trim();
    final String storeName = (store?.name ?? product.storeName).trim();
    final String description = product.description.trim();
    final bool storeClosed = store != null && !store.isOpen;
    final bool canOrder = product.isAvailable && !storeClosed;

    return SafeArea(
      child: Column(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: 1.15,
                    child: ProductImage(
                      url: product.imageUrl,
                      borderRadius: 16,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (category.isNotEmpty) ...<Widget>[
                    Chip(
                      label: Text(category),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: AppColors.placeholder,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    product.name.trim().isEmpty
                        ? 'Product'
                        : product.name.trim(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatPeso(product.price + _selectedPriceAdjustment),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (storeName.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: product.sellerId.isEmpty ? null : _openStore,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: <Widget>[
                            const Icon(Icons.storefront_outlined, size: 20),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                storeName,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      decoration: product.sellerId.isEmpty
                                          ? null
                                          : TextDecoration.underline,
                                    ),
                              ),
                            ),
                            if (product.sellerId.isNotEmpty)
                              const Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Icon(
                        canOrder
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                        size: 20,
                        color: canOrder
                            ? Colors.green.shade700
                            : Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          storeClosed
                              ? 'This store is closed right now'
                              : product.isAvailable
                              ? 'Available'
                              : 'Currently unavailable',
                        ),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 24),
                    Text(
                      'Description',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                  for (final ProductOptionGroup group in product.optionGroups)
                    _buildOptionGroup(group),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: canOrder && !_addingToCart ? _addToCart : null,
                    icon: _addingToCart
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.add_shopping_cart),
                    label: Text(
                      _addingToCart
                          ? 'Adding...'
                          : canOrder
                          ? 'Add to Cart'
                          : storeClosed
                          ? 'Store closed'
                          : 'Unavailable',
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: _favorites,
                  builder: (BuildContext context, Widget? child) {
                    final bool isFavorite = _favorites.contains(product.id);

                    return TextButton.icon(
                      onPressed: !_favoritesReady || _updatingFavorite
                          ? null
                          : _toggleFavorite,
                      icon: _updatingFavorite
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: isFavorite ? AppColors.accent : null,
                            ),
                      label: Text(
                        !_favoritesReady
                            ? 'Loading favorites...'
                            : isFavorite
                            ? 'Remove from Favorites'
                            : 'Add to Favorites',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  double get _selectedPriceAdjustment {
    return widget.product.optionGroups
        .where(
          (ProductOptionGroup group) =>
              group.type == ProductOptionType.singleChoice,
        )
        .fold<double>(0, (double total, ProductOptionGroup group) {
          final String? selected = _selectedOptions[group.name] as String?;
          if (selected == null) return total;
          for (final ProductOptionChoice choice in group.choices) {
            if (choice.label == selected) {
              return total + choice.priceAdjustment;
            }
          }
          return total;
        });
  }

  Widget _buildOptionGroup(ProductOptionGroup group) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${group.name}${group.required ? ' *' : ''}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (group.type == ProductOptionType.singleChoice)
            RadioGroup<String>(
              groupValue: _selectedOptions[group.name] as String?,
              onChanged: (String? value) {
                if (value == null) return;
                setState(() => _selectedOptions[group.name] = value);
              },
              child: Column(
                children: <Widget>[
                  for (final ProductOptionChoice choice in group.choices)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: choice.label,
                      title: Text(choice.label),
                      secondary: choice.priceAdjustment == 0
                          ? null
                          : Text(
                              '${choice.priceAdjustment > 0 ? '+' : ''}${formatPeso(choice.priceAdjustment)}',
                            ),
                    ),
                ],
              ),
            )
          else if (group.type == ProductOptionType.tags)
            for (final ProductOptionChoice choice in group.choices)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value:
                    ((_selectedOptions[group.name] as List<Object?>?) ??
                            <Object?>[])
                        .contains(choice.label),
                onChanged: (bool? checked) {
                  final List<Object?> selected = List<Object?>.of(
                    (_selectedOptions[group.name] as List<Object?>?) ??
                        <Object?>[],
                  );
                  if (checked == true) {
                    selected.add(choice.label);
                  } else {
                    selected.remove(choice.label);
                  }
                  setState(() => _selectedOptions[group.name] = selected);
                },
                title: Text(choice.label),
              )
          else
            TextField(
              controller: _optionTextControllers[group.name],
              maxLength: 100,
              decoration: const InputDecoration(
                hintText: 'Enter your message',
                border: OutlineInputBorder(),
              ),
            ),
        ],
      ),
    );
  }
}
