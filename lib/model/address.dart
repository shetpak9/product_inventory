class Address {
  const Address({
    this.id = '',
    required this.label,
    required this.recipient,
    required this.phone,
    required this.street,
    required this.barangay,
    required this.city,
    required this.province,
    this.postalCode,
    this.notes,
    this.isDefault = false,
    this.updatedAt,
  });

  final String id;
  final String label;
  final String recipient;
  final String phone;
  final String street;
  final String barangay;
  final String city;
  final String province;
  final String? postalCode;
  final String? notes;
  final bool isDefault;
  final int? updatedAt;

  String get oneLine => <String>[
    street,
    barangay,
    city,
    province,
    if (postalCode?.isNotEmpty == true) postalCode!,
  ].where((String part) => part.trim().isNotEmpty).join(', ');

  Map<String, Object?> toMap() => <String, Object?>{
    'label': label,
    'recipient': recipient,
    'phone': phone,
    'street': street,
    'barangay': barangay,
    'city': city,
    'province': province,
    if (postalCode?.isNotEmpty == true) 'postalCode': postalCode,
    if (notes?.isNotEmpty == true) 'notes': notes,
    'isDefault': isDefault,
    'updatedAt': updatedAt,
  };

  Map<String, Object?> toOrderMap() => <String, Object?>{
    'label': label,
    'recipient': recipient,
    'phone': phone,
    'street': street,
    'barangay': barangay,
    'city': city,
    'province': province,
    if (postalCode?.isNotEmpty == true) 'postalCode': postalCode,
    if (notes?.isNotEmpty == true) 'notes': notes,
  };

  factory Address.fromMap(Map<dynamic, dynamic> map, String id) {
    return Address(
      id: id,
      label: map['label']?.toString() ?? '',
      recipient: map['recipient']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      street: map['street']?.toString() ?? '',
      barangay: map['barangay']?.toString() ?? '',
      city: map['city']?.toString() ?? '',
      province: map['province']?.toString() ?? '',
      postalCode: map['postalCode']?.toString(),
      notes: map['notes']?.toString(),
      isDefault: map['isDefault'] as bool? ?? false,
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }
}
