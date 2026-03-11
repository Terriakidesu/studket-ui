import 'package:flutter/material.dart';

import 'api/user_realtime_service.dart';
import 'components/studket_app_bar.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  bool _isMarkingAllRead = false;

  Future<void> _markAllAsRead() async {
    if (_isMarkingAllRead) {
      return;
    }
    setState(() {
      _isMarkingAllRead = true;
    });
    try {
      await _realtime.markAllNotificationsRead();
    } finally {
      if (mounted) {
        setState(() {
          _isMarkingAllRead = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StudketAppBar(
        title: 'Notifications',
        actions: [
          AnimatedBuilder(
            animation: _realtime,
            builder: (BuildContext context, _) {
              final bool hasUnread = _realtime.notifications.any(
                (UserRealtimeNotification item) => !item.isRead,
              );
              return TextButton(
                onPressed: hasUnread && !_isMarkingAllRead
                    ? _markAllAsRead
                    : null,
                child: _isMarkingAllRead
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        'Mark all',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          final List<UserRealtimeNotification> notifications =
              _realtime.notifications;

          if (notifications.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'No notifications yet. New realtime notifications will appear here.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final UserRealtimeNotification notification =
                  notifications[index];
              return ListTile(
                tileColor: notification.isRead ? null : Colors.blue[50],
                title: Text(
                  notification.title,
                  style: TextStyle(
                    fontWeight: notification.isRead
                        ? FontWeight.w500
                        : FontWeight.w700,
                  ),
                ),
                subtitle: Text(notification.body),
                trailing: notification.isRead
                    ? const Icon(Icons.done_all, size: 18)
                    : TextButton(
                        onPressed: () {
                          _realtime.markNotificationRead(
                            notification.notificationId,
                          );
                        },
                        child: const Text('Read'),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}
