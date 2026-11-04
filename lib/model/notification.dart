class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.orderId,
    this.read = false,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final int? createdAt;
  final String? orderId;
  final bool read;

  factory AppNotification.fromMap(Map<dynamic, dynamic> map, String id) {
    return AppNotification(
      id: id,
      type: map['type']?.toString() ?? 'general',
      title: map['title']?.toString() ?? 'Notification',
      body: map['body']?.toString() ?? '',
      createdAt: (map['createdAt'] as num?)?.toInt(),
      orderId: map['orderId']?.toString(),
      read: map['read'] as bool? ?? false,
    );
  }
}
