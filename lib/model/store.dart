class Store {
  const Store({
    required this.ownerId,
    required this.name,
    this.description = '',
    this.phone = '',
    this.address = '',
    this.logoUrl,
    this.isOpen = true,
    this.pickupEnabled = true,
    this.deliveryEnabled = true,
    this.deliveryFee = 0,
    this.leadTimeDays = 0,
    this.maxAdvanceDays = 30,
    this.closedDates = const <String>[],
  });

  /// The seller's uid. Also the key under `stores/`.
  final String ownerId;
  final String name;
  final String description;
  final String phone;
  final String address;
  final String? logoUrl;
  final bool isOpen;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final double deliveryFee;
  final int leadTimeDays;
  final int maxAdvanceDays;
  final List<String> closedDates;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'description': description,
      'phone': phone,
      'address': address,
      'logoUrl': logoUrl,
      'isOpen': isOpen,
      'fulfillment': <String, Object?>{
        'pickupEnabled': pickupEnabled,
        'deliveryEnabled': deliveryEnabled,
        'deliveryFee': deliveryFee,
        'leadTimeDays': leadTimeDays,
        'maxAdvanceDays': maxAdvanceDays,
        'closedDates': <String, bool>{
          for (final String date in closedDates) date: true,
        },
      },
    };
  }

  factory Store.fromMap(Map<dynamic, dynamic> map, String ownerId) {
    final Map<dynamic, dynamic> fulfillment = map['fulfillment'] is Map
        ? map['fulfillment'] as Map<dynamic, dynamic>
        : map;
    final Object? rawClosedDates =
        fulfillment['closedDates'] ?? map['closedDates'];
    return Store(
      ownerId: ownerId,
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      logoUrl: map['logoUrl']?.toString(),
      isOpen: map['isOpen'] as bool? ?? true,
      pickupEnabled:
          fulfillment['pickupEnabled'] as bool? ??
          map['pickupEnabled'] as bool? ??
          true,
      deliveryEnabled:
          fulfillment['deliveryEnabled'] as bool? ??
          map['deliveryEnabled'] as bool? ??
          true,
      deliveryFee:
          (fulfillment['deliveryFee'] as num?)?.toDouble() ??
          (map['deliveryFee'] as num?)?.toDouble() ??
          0,
      leadTimeDays:
          (fulfillment['leadTimeDays'] as num?)?.toInt() ??
          (map['leadTimeDays'] as num?)?.toInt() ??
          0,
      maxAdvanceDays:
          (fulfillment['maxAdvanceDays'] as num?)?.toInt() ??
          (map['maxAdvanceDays'] as num?)?.toInt() ??
          30,
      closedDates: rawClosedDates is List
          ? rawClosedDates.map((dynamic date) => date.toString()).toList()
          : rawClosedDates is Map
          ? rawClosedDates.keys.map((dynamic date) => date.toString()).toList()
          : const <String>[],
    );
  }
}
