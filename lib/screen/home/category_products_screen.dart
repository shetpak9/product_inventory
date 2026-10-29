import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/home/product_grid_tile.dart';
import 'package:product_inventory/service/database.dart';

class CategoryProductsScreen extends StatefulWidget {
  const CategoryProductsScreen({super.key, required this.category});

  final String category;

  @override
  State<CategoryProductsScreen> createState() => _CategoryProductsScreenState();
}

class _CategoryProductsScreenState extends State<CategoryProductsScreen> {
  late final Stream<List<Product>> _products = DatabaseService().products;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: StreamBuilder<List<Product>>(
        stream: _products,
        builder: (BuildContext context, AsyncSnapshot<List<Product>> snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Unable to load products: ${snapshot.error}'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final String selectedCategory = widget.category.toLowerCase();
          final List<Product> products = snapshot.data!
              .where(
                (Product product) =>
                    product.category.trim().toLowerCase() == selectedCategory,
              )
              .toList();
          if (products.isEmpty) {
            return Center(
              child: Text('No products in ${widget.category} yet.'),
            );
          }
          return ProductGrid(products: products);
        },
      ),
    );
  }
}
