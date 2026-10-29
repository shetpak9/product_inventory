import 'package:flutter/material.dart';
import 'package:product_inventory/shared/app_theme.dart';

/// Product photo that fills whatever space its parent gives it
/// (wrap it in AspectRatio or SizedBox), with a placeholder when missing.
class ProductImage extends StatelessWidget {
  const ProductImage({super.key, required this.url, this.borderRadius = 8});

  final String? url;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = url;
    const Widget placeholder = ColoredBox(
      color: AppColors.placeholder,
      child: Center(child: Icon(Icons.bakery_dining, size: 32)),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.expand(
        child: (imageUrl == null || imageUrl.isEmpty)
            ? placeholder
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (_, Widget child, ImageChunkEvent? progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}
