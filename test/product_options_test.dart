import 'package:flutter_test/flutter_test.dart';
import 'package:product_inventory/model/cart.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';

void main() {
  test('product option groups and price adjustments round-trip', () {
    final Product product = Product(
      id: 'cake',
      name: 'Cake',
      price: 100,
      optionGroups: const <ProductOptionGroup>[
        ProductOptionGroup(
          name: 'Size',
          type: ProductOptionType.singleChoice,
          required: true,
          choices: <ProductOptionChoice>[
            ProductOptionChoice(label: 'Small'),
            ProductOptionChoice(label: 'Large', priceAdjustment: 50),
          ],
        ),
        ProductOptionGroup(name: 'Message', type: ProductOptionType.freeText),
        ProductOptionGroup(
          name: 'Allergens',
          type: ProductOptionType.tags,
          choices: <ProductOptionChoice>[
            ProductOptionChoice(label: 'Contains nuts'),
          ],
        ),
      ],
    );

    final Product restored = Product.fromMap(product.toMap(), product.id);
    expect(restored.optionGroups, hasLength(3));
    expect(restored.optionGroups.first.choices.last.priceAdjustment, 50);
    expect(restored.optionGroups[2].type, ProductOptionType.tags);
  });

  test('cart lines with different choices have separate identities', () {
    final CartItem small = CartItem(
      id: 'small',
      productId: 'cake',
      productName: 'Cake',
      price: 100,
      selectedOptions: const <String, Object?>{'Size': 'Small'},
    );
    final CartItem large = CartItem(
      id: 'large',
      productId: 'cake',
      productName: 'Cake',
      price: 100,
      selectedOptions: const <String, Object?>{'Size': 'Large'},
      priceAdjustment: 50,
    );
    expect(small.optionsIdentity, isNot(large.optionsIdentity));

    final CartItem restored = CartItem.fromMap(large.toMap(), large.id);
    expect(restored.selectedOptions, large.selectedOptions);
    expect(restored.priceAdjustment, 50);
    expect(restored.lineTotal, 150);
  });

  test('order items retain selections and adjusted pricing', () {
    final OrderItem item = OrderItem(
      productId: 'cake',
      productName: 'Cake',
      price: 100,
      quantity: 2,
      selectedOptions: const <String, Object?>{
        'Size': 'Large',
        'Allergens': <String>['Contains nuts'],
      },
      priceAdjustment: 50,
    );
    final OrderItem restored = OrderItem.fromMap(item.toMap());
    expect(restored.selectedOptions, item.selectedOptions);
    expect(restored.priceAdjustment, 50);
    expect(restored.lineTotal, 300);
  });
}
