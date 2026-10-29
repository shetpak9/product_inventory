import 'dart:convert';

class CartItem {
  const CartItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.price,
    this.sellerId = '',
    this.storeName = '',
    this.imageUrl,
    this.quantity = 1,
    this.selectedOptions = const <String, Object?>{},
    this.priceAdjustment = 0,
  });

  final String id;
  final String productId;
  final String productName;
  final double price;
  final String sellerId;
  final String storeName;
  final String? imageUrl;
  final int quantity;
  final Map<String, Object?> selectedOptions;
  final double priceAdjustment;

  double get lineTotal => (price + priceAdjustment) * quantity;

  String get optionsIdentity {
    final List<String> keys = selectedOptions.keys.toList()..sort();
    return jsonEncode(<String, Object?>{
      'options': <String, Object?>{
        for (final String key in keys) key: selectedOptions[key],
      },
      'priceAdjustment': priceAdjustment,
    });
  }

  CartItem copyWith({
    String? id,
    String? sellerId,
    String? storeName,
    int? quantity,
    Map<String, Object?>? selectedOptions,
    double? priceAdjustment,
  }) {
    return CartItem(
      id: id ?? this.id,
      productId: productId,
      productName: productName,
      price: price,
      sellerId: sellerId ?? this.sellerId,
      storeName: storeName ?? this.storeName,
      imageUrl: imageUrl,
      quantity: quantity ?? this.quantity,
      selectedOptions: selectedOptions ?? this.selectedOptions,
      priceAdjustment: priceAdjustment ?? this.priceAdjustment,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'productId': productId,
      'productName': productName,
      'price': price,
      'sellerId': sellerId,
      'storeName': storeName,
      'imageUrl': imageUrl,
      'quantity': quantity,
      if (selectedOptions.isNotEmpty) 'selectedOptions': selectedOptions,
      'priceAdjustment': priceAdjustment,
    };
  }

  /// Older cart rows have no seller/store, quantity, or image metadata.
  factory CartItem.fromMap(Map<dynamic, dynamic> map, String id) {
    return CartItem(
      id: id,
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      sellerId: map['sellerId']?.toString() ?? '',
      storeName: map['storeName']?.toString() ?? '',
      imageUrl: map['imageUrl']?.toString(),
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      selectedOptions: map['selectedOptions'] is Map
          ? Map<String, Object?>.from(map['selectedOptions'] as Map)
          : const <String, Object?>{},
      priceAdjustment: (map['priceAdjustment'] as num?)?.toDouble() ?? 0,
    );
  }
}
