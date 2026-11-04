import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/review.dart';
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

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  final ProductReview review;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    review.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ...List<Widget>.generate(
                  5,
                  (int index) => Icon(
                    index < review.rating ? Icons.star : Icons.star_border,
                    size: 18,
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            if (review.comment.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(review.comment),
            ],
            if (canEdit)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                  TextButton(onPressed: onDelete, child: const Text('Delete')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({
    required this.productId,
    required this.orderId,
    this.existing,
  });

  final String productId;
  final String orderId;
  final ProductReview? existing;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late int _rating = widget.existing?.rating ?? 5;
  late final TextEditingController _commentController = TextEditingController(
    text: widget.existing?.comment ?? '',
  );

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submit() {
    final String comment = _commentController.text.trim();
    if (comment.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Review must be 500 characters or less.')),
      );
      return;
    }
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final String name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : user.email?.trim().isNotEmpty == true
        ? user.email!.trim()
        : 'Customer';
    Navigator.of(context).pop(
      ProductReview(
        id: widget.orderId,
        productId: widget.productId,
        orderId: widget.orderId,
        customerId: user.uid,
        customerName: name.length > 100 ? name.substring(0, 100) : name,
        rating: _rating,
        comment: comment,
        createdAt: widget.existing?.createdAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Write a review' : 'Edit review'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(
                5,
                (int index) => IconButton(
                  onPressed: () => setState(() => _rating = index + 1),
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                  ),
                ),
              ),
            ),
            TextField(
              controller: _commentController,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Share your experience (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final FavoritesStore _favorites = FavoritesStore.instance;
  final DatabaseService _db = DatabaseService();

  // Older products have no seller, so there is no store to watch.
  late final Stream<Store?>? _storeStream = widget.product.sellerId.isEmpty
      ? null
      : _db.storeStream(widget.product.sellerId);
  late final Stream<List<ProductReview>> _reviewsStream =
      FirebaseAuth.instance.currentUser == null
      ? Stream<List<ProductReview>>.value(<ProductReview>[])
      : _db.reviewsStream(widget.product.id);
  late final Stream<List<Order>> _customerOrdersStream =
      FirebaseAuth.instance.currentUser == null
      ? Stream<List<Order>>.value(<Order>[])
      : _db.customerOrdersStream(FirebaseAuth.instance.currentUser!.uid);

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
    final bool outOfStock =
        product.stockQuantity != null && product.stockQuantity == 0;
    final bool canOrder = product.isAvailable && !storeClosed && !outOfStock;

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
                              : outOfStock
                              ? 'Out of stock'
                              : product.isAvailable
                              ? product.stockQuantity == null
                                    ? 'Available'
                                    : '${product.stockQuantity} in stock'
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
                  const SizedBox(height: 24),
                  _buildReviews(),
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

  Widget _buildReviews() {
    return StreamBuilder<List<ProductReview>>(
      stream: _reviewsStream,
      builder:
          (
            BuildContext context,
            AsyncSnapshot<List<ProductReview>> reviewSnapshot,
          ) {
            if (reviewSnapshot.hasError) {
              return const Text('Reviews are temporarily unavailable.');
            }
            if (!reviewSnapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final List<ProductReview> reviews = reviewSnapshot.data!;
            final double average = reviews.isEmpty
                ? 0
                : reviews.fold<int>(
                        0,
                        (int total, ProductReview review) =>
                            total + review.rating,
                      ) /
                      reviews.length;
            return StreamBuilder<List<Order>>(
              stream: _customerOrdersStream,
              builder:
                  (
                    BuildContext context,
                    AsyncSnapshot<List<Order>> orderSnapshot,
                  ) {
                    final List<Order>
                    eligibleOrders = (orderSnapshot.data ?? <Order>[])
                        .where(
                          (Order order) =>
                              order.status == OrderStatus.delivered &&
                              order.reviewableProductIds[widget.product.id] ==
                                  true &&
                              order.items.any(
                                (OrderItem item) =>
                                    item.productId == widget.product.id,
                              ),
                        )
                        .toList();
                    final Set<String> reviewedOrderIds = reviews
                        .map((ProductReview review) => review.orderId)
                        .toSet();
                    final List<Order> unreviewedOrders = eligibleOrders
                        .where(
                          (Order order) => !reviewedOrderIds.contains(order.id),
                        )
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Reviews',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.star, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              reviews.isEmpty
                                  ? 'No ratings yet'
                                  : '${average.toStringAsFixed(1)} (${reviews.length})',
                            ),
                          ],
                        ),
                        if (unreviewedOrders.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () =>
                                  _editReview(order: unreviewedOrders.first),
                              icon: const Icon(Icons.rate_review_outlined),
                              label: const Text('Write a review'),
                            ),
                          ),
                        if (reviews.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text('Be the first to review this product.'),
                          ),
                        for (final ProductReview review in reviews)
                          _ReviewTile(
                            review: review,
                            canEdit:
                                review.customerId ==
                                FirebaseAuth.instance.currentUser?.uid,
                            onEdit: () {
                              final List<Order> matchingOrders = eligibleOrders
                                  .where(
                                    (Order order) => order.id == review.orderId,
                                  )
                                  .toList();
                              _editReview(
                                order: matchingOrders.isEmpty
                                    ? null
                                    : matchingOrders.first,
                                existing: review,
                              );
                            },
                            onDelete: () => _deleteReview(review),
                          ),
                      ],
                    );
                  },
            );
          },
    );
  }

  Future<void> _editReview({
    required Order? order,
    ProductReview? existing,
  }) async {
    if (order == null && existing == null) return;
    final ProductReview? review = await showDialog<ProductReview>(
      context: context,
      builder: (_) => _ReviewDialog(
        productId: widget.product.id,
        orderId: existing?.orderId ?? order!.id,
        existing: existing,
      ),
    );
    if (review == null) return;
    try {
      await _db.saveReview(review);
      _snack('Review saved.');
    } catch (error) {
      debugPrint('Review save failed: $error');
      _snack('Could not save your review. Please try again.');
    }
  }

  Future<void> _deleteReview(ProductReview review) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete review?'),
        content: const Text('Your review will be removed from this product.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.deleteReview(review);
      _snack('Review deleted.');
    } catch (error) {
      debugPrint('Review delete failed: $error');
      _snack('Could not delete your review. Please try again.');
    }
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
