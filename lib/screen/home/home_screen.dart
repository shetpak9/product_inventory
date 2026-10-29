import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/home/product_grid_tile.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Stream<List<Product>> _products = DatabaseService().products;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
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

        final List<Product> products = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: double.infinity,
                  height: 154,
                  child: Image.asset(
                    'assets/ceb597078ba4528580b5d90fbf13a170.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: AppColors.placeholder,
                      child: Center(
                        child: Icon(Icons.bakery_dining_outlined, size: 48),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Our Best Sellers',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (products.isEmpty)
              const Expanded(
                child: Center(child: Text('No products available yet.')),
              )
            else
              Expanded(
                child: ProductGrid(
                  products: products,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                ),
              ),
          ],
        );
      },
    );
  }
}
