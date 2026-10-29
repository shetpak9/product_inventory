import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/home/product_detail.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_image.dart';

/// 3-column grid used on Home, Category and Search results.
const SliverGridDelegateWithFixedCrossAxisCount kProductGridDelegate =
    SliverGridDelegateWithFixedCrossAxisCount(
  crossAxisCount: 3,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  childAspectRatio: 0.66,
);

class ProductGridTile extends StatelessWidget {
  const ProductGridTile({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductDetailScreen(product: product),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: ProductImage(url: product.imageUrl),
          ),
          const SizedBox(height: 6),
          Text(
            product.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(formatPeso(product.price)),
        ],
      ),
    );
  }
}

/// Scrollable grid of [ProductGridTile]s.
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required this.products,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
  });

  final List<Product> products;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: kProductGridDelegate,
      itemCount: products.length,
      itemBuilder: (BuildContext context, int index) {
        return ProductGridTile(product: products[index]);
      },
    );
  }
}
