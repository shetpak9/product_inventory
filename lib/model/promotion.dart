enum PromotionType { percentage, fixed }

class Promotion {
  const Promotion({
    required this.id,
    required this.sellerId,
    required this.code,
    required this.type,
    required this.value,
    required this.startsAt,
    required this.endsAt,
    required this.minOrderAmount,
    this.usageLimit,
    this.usageCount = 0,
    this.productId,
  });

  final String id;
  final String sellerId;
  final String code;
  final PromotionType type;
  final double value;
  final int startsAt;
  final int endsAt;
  final double minOrderAmount;
  final int? usageLimit;
  final int usageCount;
  final String? productId;

  factory Promotion.fromMap(Map<dynamic, dynamic> map, String id) {
    return Promotion(
      id: id,
      sellerId: map['sellerId']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      type: map['type'] == 'fixed'
          ? PromotionType.fixed
          : PromotionType.percentage,
      value: (map['value'] as num?)?.toDouble() ?? 0,
      startsAt: (map['startsAt'] as num?)?.toInt() ?? 0,
      endsAt: (map['endsAt'] as num?)?.toInt() ?? 0,
      minOrderAmount: (map['minOrderAmount'] as num?)?.toDouble() ?? 0,
      usageLimit: (map['usageLimit'] as num?)?.toInt(),
      usageCount: (map['usageCount'] as num?)?.toInt() ?? 0,
      productId: map['productId']?.toString(),
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'sellerId': sellerId,
    'code': code,
    'type': type == PromotionType.fixed ? 'fixed' : 'percentage',
    'value': value,
    'startsAt': startsAt,
    'endsAt': endsAt,
    'minOrderAmount': minOrderAmount,
    if (usageLimit != null) 'usageLimit': usageLimit,
    'usageCount': usageCount,
    if (productId != null && productId!.isNotEmpty) 'productId': productId,
  };
}
