class ProductReview {
  const ProductReview({
    required this.id,
    required this.productId,
    required this.orderId,
    required this.customerId,
    required this.customerName,
    required this.rating,
    required this.comment,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String orderId;
  final String customerId;
  final String customerName;
  final int rating;
  final String comment;
  final int? createdAt;
  final int? updatedAt;

  factory ProductReview.fromMap(Map<dynamic, dynamic> map, String id) {
    return ProductReview(
      id: id,
      productId: map['productId']?.toString() ?? '',
      orderId: map['orderId']?.toString() ?? '',
      customerId: map['customerId']?.toString() ?? '',
      customerName: map['customerName']?.toString() ?? 'Customer',
      rating: (map['rating'] as num?)?.toInt() ?? 0,
      comment: map['comment']?.toString() ?? '',
      createdAt: (map['createdAt'] as num?)?.toInt(),
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }

  Map<String, Object?> toMap({bool includeCreatedAt = true}) {
    return <String, Object?>{
      'productId': productId,
      'orderId': orderId,
      'customerId': customerId,
      'customerName': customerName,
      'rating': rating,
      'comment': comment,
      if (includeCreatedAt) 'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
