class ProductCategories {
  const ProductCategories._();

  static const List<String> all = <String>[
    'Cakes',
    'Pastries',
    'Breads',
    'Seasonal Items',
  ];
}

enum ProductOptionType {
  singleChoice('singleChoice'),
  freeText('freeText'),
  tags('tags');

  const ProductOptionType(this.dbValue);

  final String dbValue;

  static ProductOptionType fromDbValue(String? value) {
    return ProductOptionType.values.firstWhere(
      (ProductOptionType type) => type.dbValue == value,
      orElse: () => ProductOptionType.singleChoice,
    );
  }
}

class ProductOptionChoice {
  const ProductOptionChoice({required this.label, this.priceAdjustment = 0});

  final String label;
  final double priceAdjustment;

  Map<String, Object?> toMap() => <String, Object?>{
    'label': label,
    'priceAdjustment': priceAdjustment,
  };

  factory ProductOptionChoice.fromMap(Map<dynamic, dynamic> map) {
    return ProductOptionChoice(
      label: map['label']?.toString() ?? '',
      priceAdjustment: (map['priceAdjustment'] as num?)?.toDouble() ?? 0,
    );
  }
}

class ProductOptionGroup {
  const ProductOptionGroup({
    required this.name,
    required this.type,
    this.required = false,
    this.choices = const <ProductOptionChoice>[],
  });

  final String name;
  final ProductOptionType type;
  final bool required;
  final List<ProductOptionChoice> choices;

  Map<String, Object?> toMap() => <String, Object?>{
    'name': name,
    'type': type.dbValue,
    'required': required,
    'choices': <String, Object?>{
      for (int index = 0; index < choices.length; index++)
        '$index': choices[index].toMap(),
    },
  };

  factory ProductOptionGroup.fromMap(Map<dynamic, dynamic> map) {
    final Object? rawChoices = map['choices'];
    final List<ProductOptionChoice> choices = <ProductOptionChoice>[];
    if (rawChoices is Map) {
      final List<MapEntry<dynamic, dynamic>> entries =
          rawChoices.entries
              .where((MapEntry<dynamic, dynamic> entry) => entry.value is Map)
              .toList()
            ..sort(
              (MapEntry<dynamic, dynamic> a, MapEntry<dynamic, dynamic> b) =>
                  (int.tryParse(a.key.toString()) ?? 0).compareTo(
                    int.tryParse(b.key.toString()) ?? 0,
                  ),
            );
      for (final MapEntry<dynamic, dynamic> entry in entries) {
        choices.add(ProductOptionChoice.fromMap(entry.value as Map));
      }
    } else if (rawChoices is List) {
      for (final dynamic choice in rawChoices) {
        if (choice is Map) {
          choices.add(ProductOptionChoice.fromMap(choice));
        }
      }
    }
    return ProductOptionGroup(
      name: map['name']?.toString() ?? '',
      type: ProductOptionType.fromDbValue(map['type']?.toString()),
      required: map['required'] as bool? ?? false,
      choices: choices,
    );
  }
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
    this.description = '',
    this.imageUrl,
    this.sellerId = '',
    this.storeName = '',
    this.category = '',
    this.isAvailable = true,
    this.maxPerDay,
    this.stockQuantity,
    this.optionGroups = const <ProductOptionGroup>[],
  });

  final String id;
  final String name;
  final double price;
  final String description;
  final String? imageUrl;
  final String sellerId;
  final String storeName;
  final String category;
  final bool isAvailable;
  final int? maxPerDay;
  final int? stockQuantity;
  final List<ProductOptionGroup> optionGroups;

  /// Tolerates older products that only have `name` and `price`.
  factory Product.fromMap(Map<dynamic, dynamic> map, String id) {
    return Product(
      id: id,
      name: map['name']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      description: map['description']?.toString() ?? '',
      imageUrl: map['imageUrl']?.toString(),
      sellerId: map['sellerId']?.toString() ?? '',
      storeName: map['storeName']?.toString() ?? '',
      category: map['category']?.toString() ?? '',
      isAvailable: map['isAvailable'] as bool? ?? true,
      maxPerDay: (map['maxPerDay'] as num?)?.toInt(),
      stockQuantity: (map['stockQuantity'] as num?)?.toInt(),
      optionGroups: map['optionGroups'] is Map
          ? (map['optionGroups'] as Map<dynamic, dynamic>).entries
                .where((MapEntry<dynamic, dynamic> entry) => entry.value is Map)
                .map(
                  (MapEntry<dynamic, dynamic> entry) =>
                      ProductOptionGroup.fromMap(entry.value as Map),
                )
                .toList()
          : map['optionGroups'] is List
          ? (map['optionGroups'] as List<dynamic>)
                .whereType<Map>()
                .map(ProductOptionGroup.fromMap)
                .toList()
          : const <ProductOptionGroup>[],
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'price': price,
      'description': description,
      'imageUrl': imageUrl,
      'sellerId': sellerId,
      'storeName': storeName,
      'category': category,
      'isAvailable': isAvailable,
      if (maxPerDay != null) 'maxPerDay': maxPerDay,
      if (stockQuantity != null) 'stockQuantity': stockQuantity,
      if (optionGroups.isNotEmpty)
        'optionGroups': <String, Object?>{
          for (int index = 0; index < optionGroups.length; index++)
            '$index': optionGroups[index].toMap(),
        },
    };
  }
}
