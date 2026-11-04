import 'package:flutter/material.dart';
import 'package:product_inventory/model/notification.dart';
import 'package:product_inventory/service/auth_service.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/app_theme.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String? uid = AuthService().currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to view notifications.')),
      );
    }
    final DatabaseService database = DatabaseService();
    Future<void> markAllRead() async {
      try {
        await database.markAllNotificationsRead(uid);
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not mark notifications as read: $error'),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          TextButton(
            onPressed: markAllRead,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: database.notificationsStream(uid),
        builder:
            (
              BuildContext context,
              AsyncSnapshot<List<AppNotification>> snapshot,
            ) {
              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    'Could not load notifications: ${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final List<AppNotification> notifications = snapshot.data!;
              if (notifications.isEmpty) {
                return const Center(child: Text('No notifications yet.'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: notifications.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final AppNotification notification = notifications[index];
                  Future<void> markRead() async {
                    try {
                      await database.markNotificationRead(uid, notification.id);
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not update notification: $error',
                          ),
                        ),
                      );
                    }
                  }

                  return ListTile(
                    leading: Icon(
                      notification.read
                          ? Icons.notifications_none
                          : Icons.notifications_active,
                      color: notification.read ? null : AppColors.accent,
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.read
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(notification.body),
                    onTap: notification.read ? null : markRead,
                  );
                },
              );
            },
      ),
    );
  }
}
