import 'package:flutter/material.dart';

/// Square product/store image with a placeholder when there is no photo.
class ProductThumb extends StatelessWidget {
  const ProductThumb({super.key, required this.url, this.size = 56});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = url;
    final Widget placeholder = const ColoredBox(
      color: Color(0xFFEFE6DA),
      child: Center(child: Icon(Icons.cake_outlined)),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
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
