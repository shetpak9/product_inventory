import 'package:flutter/material.dart';

enum OrderStatus {
  pending('pending', 'Pending', Colors.amber),
  accepted('accepted', 'Accepted', Colors.blue),
  baking('baking', 'Baking', Colors.deepOrange),
  ready('ready', 'Ready', Colors.green),
  outForDelivery('out_for_delivery', 'Out for delivery', Colors.purple),
  delivered('delivered', 'Delivered', Colors.teal),
  cancelled('cancelled', 'Cancelled', Colors.red);

  const OrderStatus(this.dbValue, this.label, this.color);

  final String dbValue;
  final String label;
  final Color color;

  static OrderStatus fromDbValue(String? value) {
    return OrderStatus.values.firstWhere(
      (OrderStatus status) => status.dbValue == value,
      orElse: () => OrderStatus.pending,
    );
  }
}

enum FulfillmentType {
  pickup('pickup', 'Pickup'),
  delivery('delivery', 'Delivery');

  const FulfillmentType(this.dbValue, this.label);

  final String dbValue;
  final String label;

  static FulfillmentType fromDbValue(String? value) {
    return FulfillmentType.values.firstWhere(
      (FulfillmentType type) => type.dbValue == value,
      orElse: () => FulfillmentType.pickup,
    );
  }
}

class OrderFulfillment {
  const OrderFulfillment({
    required this.type,
    required this.date,
    this.timeSlot,
    this.address,
  });

  final FulfillmentType type;
  final String date;
  final String? timeSlot;
  final Map<String, Object?>? address;

  String get timeSlotLabel => switch (timeSlot) {
    'morning' => 'Morning',
    'afternoon' => 'Afternoon',
    _ => '',
  };

  String get addressOneLine {
    final Map<String, Object?>? snapshot = address;
    if (snapshot == null) return '';
    return <String>[
      snapshot['street']?.toString() ?? '',
      snapshot['barangay']?.toString() ?? '',
      snapshot['city']?.toString() ?? '',
      snapshot['province']?.toString() ?? '',
      snapshot['postalCode']?.toString() ?? '',
    ].where((String part) => part.trim().isNotEmpty).join(', ');
  }

  String get addressRecipient => address?['recipient']?.toString() ?? '';
  String get addressPhone => address?['phone']?.toString() ?? '';
  String get addressLabel => address?['label']?.toString() ?? '';
  String get addressNotes => address?['notes']?.toString() ?? '';

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type.dbValue,
    'date': date,
    if (timeSlot != null) 'timeSlot': timeSlot,
    if (type == FulfillmentType.delivery && address != null) 'address': address,
  };

  factory OrderFulfillment.fromMap(Map<dynamic, dynamic>? map) {
    final Object? rawAddress = map?['address'];
    return OrderFulfillment(
      type: FulfillmentType.fromDbValue(map?['type']?.toString()),
      date: map?['date']?.toString() ?? '',
      timeSlot: map?['timeSlot']?.toString(),
      address: rawAddress is Map
          ? Map<String, Object?>.from(rawAddress)
          : rawAddress is String
          ? <String, Object?>{
              'label': 'Delivery address',
              'recipient': '',
              'phone': '',
              'street': rawAddress,
              'barangay': '',
              'city': '',
              'province': '',
            }
          : null,
    );
  }
}

List<OrderStatus> nextStatuses(
  OrderStatus current, {
  FulfillmentType fulfillmentType = FulfillmentType.delivery,
}) {
  return switch (current) {
    OrderStatus.pending => <OrderStatus>[
      OrderStatus.accepted,
      OrderStatus.cancelled,
    ],
    OrderStatus.accepted => <OrderStatus>[
      OrderStatus.baking,
      OrderStatus.cancelled,
    ],
    OrderStatus.baking => <OrderStatus>[OrderStatus.ready],
    OrderStatus.ready =>
      fulfillmentType == FulfillmentType.pickup
          ? <OrderStatus>[OrderStatus.delivered]
          : <OrderStatus>[OrderStatus.outForDelivery, OrderStatus.delivered],
    OrderStatus.outForDelivery => <OrderStatus>[OrderStatus.delivered],
    OrderStatus.delivered || OrderStatus.cancelled => <OrderStatus>[],
  };
}

class OrderItem {
  const OrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.imageUrl,
    this.selectedOptions = const <String, Object?>{},
    this.priceAdjustment = 0,
  });

  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final String? imageUrl;
  final Map<String, Object?> selectedOptions;
  final double priceAdjustment;

  double get lineTotal => (price + priceAdjustment) * quantity;

  Map<String, Object?> toMap() => <String, Object?>{
    'productId': productId,
    'productName': productName,
    'price': price,
    'quantity': quantity,
    'imageUrl': imageUrl,
    if (selectedOptions.isNotEmpty) 'selectedOptions': selectedOptions,
    'priceAdjustment': priceAdjustment,
  };

  factory OrderItem.fromMap(Map<dynamic, dynamic> map) {
    return OrderItem(
      productId: map['productId']?.toString() ?? '',
      productName: map['productName']?.toString() ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      imageUrl: map['imageUrl']?.toString(),
      selectedOptions: map['selectedOptions'] is Map
          ? Map<String, Object?>.from(map['selectedOptions'] as Map)
          : const <String, Object?>{},
      priceAdjustment: (map['priceAdjustment'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Order {
  const Order({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.sellerId,
    required this.storeName,
    this.customerPhone = '',
    required this.items,
    required this.subtotal,
    required this.total,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.fulfillment = const OrderFulfillment(
      type: FulfillmentType.pickup,
      date: '',
    ),
    this.deliveryFee = 0,
    this.note,
    this.paymentMethod = 'cash',
    this.paymentStatus = 'unpaid',
  });

  final String id;
  final String customerId;
  final String customerName;
  final String sellerId;
  final String storeName;
  final String customerPhone;
  final List<OrderItem> items;
  final double subtotal;
  final double total;
  final String? note;
  final OrderStatus status;
  final String paymentMethod;
  final String paymentStatus;
  final int? createdAt;
  final int? updatedAt;
  final OrderFulfillment fulfillment;
  final double deliveryFee;

  Map<String, Object?> toMap() => <String, Object?>{
    'customerId': customerId,
    'customerName': customerName,
    'sellerId': sellerId,
    'storeName': storeName,
    'customerPhone': customerPhone,
    'items': <String, Object?>{
      for (int index = 0; index < items.length; index++)
        '$index': items[index].toMap(),
    },
    'subtotal': subtotal,
    'total': total,
    'fulfillment': fulfillment.toMap(),
    'deliveryFee': deliveryFee,
    if (note != null && note!.isNotEmpty) 'note': note,
    'status': status.dbValue,
    'paymentMethod': paymentMethod,
    'paymentStatus': paymentStatus,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory Order.fromMap(Map<dynamic, dynamic> map, String id) {
    final Object? rawItems = map['items'];
    final List<OrderItem> items = <OrderItem>[];
    if (rawItems is Map) {
      final List<MapEntry<dynamic, dynamic>> entries =
          rawItems.entries
              .where((MapEntry<dynamic, dynamic> entry) => entry.value is Map)
              .toList()
            ..sort(
              (MapEntry<dynamic, dynamic> a, MapEntry<dynamic, dynamic> b) =>
                  int.tryParse(
                    a.key.toString(),
                  )?.compareTo(int.tryParse(b.key.toString()) ?? 0) ??
                  a.key.toString().compareTo(b.key.toString()),
            );
      for (final MapEntry<dynamic, dynamic> entry in entries) {
        items.add(OrderItem.fromMap(entry.value as Map));
      }
    }

    return Order(
      id: id,
      customerId: map['customerId']?.toString() ?? '',
      customerName: map['customerName']?.toString() ?? '',
      sellerId: map['sellerId']?.toString() ?? '',
      storeName: map['storeName']?.toString() ?? '',
      customerPhone: map['customerPhone']?.toString() ?? '',
      items: items,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      fulfillment: OrderFulfillment.fromMap(
        map['fulfillment'] is Map ? map['fulfillment'] as Map : null,
      ),
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble() ?? 0,
      note: map['note']?.toString(),
      status: OrderStatus.fromDbValue(map['status']?.toString()),
      paymentMethod: map['paymentMethod']?.toString() ?? 'cash',
      paymentStatus: map['paymentStatus']?.toString() ?? 'unpaid',
      createdAt: (map['createdAt'] as num?)?.toInt(),
      updatedAt: (map['updatedAt'] as num?)?.toInt(),
    );
  }
}
