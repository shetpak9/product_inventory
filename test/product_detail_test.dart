import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/screen/home/product_detail.dart';
import 'package:product_inventory/screen/home/product_grid_tile.dart';
import 'package:product_inventory/shared/product_image.dart';

void main() {
  const Product product = Product(
    id: 'cake-1',
    name: 'Strawberry Cake',
    price: 425,
    category: 'Cakes',
    storeName: "Kate's Bakery",
    description: 'A fresh strawberry cake.',
  );

  testWidgets('product grid tile opens details for the selected product', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProductGrid(products: <Product>[product])),
      ),
    );

    await tester.tap(find.byType(ProductGridTile));
    await tester.pumpAndSettle();

    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(find.text('Strawberry Cake'), findsNWidgets(2));
    expect(find.text('Cakes'), findsOneWidget);
    expect(find.text("Kate's Bakery"), findsOneWidget);
    expect(find.text('A fresh strawberry cake.'), findsOneWidget);
    expect(find.text('₱425.00'), findsOneWidget);
    expect(find.byType(ProductImage), findsOneWidget);
    expect(find.byIcon(Icons.bakery_dining), findsOneWidget);
  });

  testWidgets(
    'unavailable product disables cart and shows missing fields safely',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const Product unavailable = Product(
        id: 'sold-out',
        name: '',
        price: 100,
        isAvailable: false,
      );
      await tester.pumpWidget(
        const MaterialApp(home: ProductDetailScreen(product: unavailable)),
      );
      await tester.pumpAndSettle();

      final ElevatedButton button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Currently unavailable'), findsOneWidget);
      expect(find.text('Description'), findsNothing);
      expect(find.text('Product'), findsOneWidget);
      expect(find.byType(ProductImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('long descriptions remain scrollable on narrow screens', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final String description = List<String>.filled(
      40,
      'Freshly baked daily.',
    ).join(' ');
    final Product longDescription = Product(
      id: 'long-description',
      name: 'Bakery Special',
      price: 80,
      description: description,
    );
    await tester.pumpWidget(
      MaterialApp(home: ProductDetailScreen(product: longDescription)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text(description), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
