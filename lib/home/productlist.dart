import 'package:flutter/material.dart';
import 'package:product_inventory/home/producttile.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/service/database.dart';

class ProductList extends StatefulWidget {
  const ProductList({super.key});

  @override
  State<ProductList> createState() => _ProductlistState();
}

class _ProductlistState extends State<ProductList> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: DatabaseService().products, 
      builder: (context, snapshot){
        if (snapshot.hasError) {
          return Text('Error: ${snapshot.error}');
        }

        if (!snapshot.hasData) {
          return const CircularProgressIndicator();
        }

        final products = snapshot.data!;

        return ListView.builder(
          itemCount: products.length,
          itemBuilder: (context, index) {
            return Producttile(
              product: products[index],
            );
          },
        );
      }
    );
  }
}