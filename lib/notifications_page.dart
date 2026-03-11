import 'package:flutter/material.dart';

import 'api/api_base_url.dart';
import 'api/user_realtime_service.dart';
import 'chats_page.dart';
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
          final List<_NotificationGroup> groups =
              _groupNotifications(notifications);

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
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final _NotificationGroup group = groups[index];
              final UserRealtimeNotification latest = group.items.first;
              final bool isUnread = group.items.any(
                (UserRealtimeNotification item) => !item.isRead,
              );
              final bool isMessageGroup = _isMessageNotification(latest);

              if (isMessageGroup) {
                final int unreadCount = group.items
                    .where((UserRealtimeNotification item) => !item.isRead)
                    .length;
                final UserRealtimeConversation? conversation =
                    _conversationForNotification(latest);
                final String senderName =
                    conversation?.title ?? _messageSenderLabel(latest);
                final bool isStaffSender = conversation != null &&
                    _isStaffAccountType(conversation.otherAccountType);

                return ListTile(
                  tileColor: isUnread ? Colors.blue[50] : null,
                  leading: _NotificationTypeIcon(notification: latest),
                  onTap: () {
                    _openMessageGroup(context, latest);
                  },
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          senderName,
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.w700 : FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isStaffSender)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8EAFF),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'Staff',
                            style: TextStyle(
                              color: Color(0xFF4752C4),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    latest.body.isNotEmpty
                        ? latest.body
                        : 'Messages from $senderName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isUnread
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '$unreadCount unread',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(height: 4),
                            GestureDetector(
                              onTap: () async {
                                for (final UserRealtimeNotification item
                                    in group.items) {
                                  if (!item.isRead) {
                                    await _realtime.markNotificationRead(
                                      item.notificationId,
                                    );
                                  }
                                }
                              },
                              child: const Text(
                                'Read all',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          ],
                        )
                      : const Icon(Icons.done_all, size: 18),
                );
              }

              return ExpansionTile(
                initiallyExpanded: index == 0,
                collapsedBackgroundColor: isUnread ? Colors.blue[50] : null,
                backgroundColor: isUnread ? Colors.blue[50] : null,
                leading: _NotificationTypeIcon(notification: latest),
                title: Text(
                  group.title,
                  style: TextStyle(
                    fontWeight: isUnread ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  group.items.length == 1
                      ? latest.body
                      : '${group.items.length} notifications',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: isUnread
                    ? TextButton(
                        onPressed: () async {
                          for (final UserRealtimeNotification item in group.items) {
                            if (!item.isRead) {
                              await _realtime.markNotificationRead(
                                item.notificationId,
                              );
                            }
                          }
                        },
                        child: const Text('Read all'),
                      )
                    : const Icon(Icons.done_all, size: 18),
                children: group.items.map((UserRealtimeNotification item) {
                  return ListTile(
                    tileColor: item.isRead ? null : Colors.blue[50],
                    leading: _NotificationTypeIcon(notification: item),
                    title: Text(
                      item.title,
                      style: TextStyle(
                        fontWeight: item.isRead
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(item.body),
                    trailing: item.isRead
                        ? const Icon(Icons.done_all, size: 18)
                        : TextButton(
                            onPressed: () {
                              _realtime.markNotificationRead(
                                item.notificationId,
                              );
                            },
                            child: const Text('Read'),
                          ),
                  );
                }).toList(growable: false),
              );
            },
          );
        },
      ),
    );
  }

  bool _isMessageNotification(UserRealtimeNotification notification) {
    final String type = notification.notificationType.toLowerCase();
    final String entity = (notification.relatedEntityType ?? '').toLowerCase();
    return type.contains('message') ||
        type.contains('chat') ||
        entity.contains('message') ||
        entity.contains('conversation') ||
        entity.contains('chat');
  }

  UserRealtimeConversation? _conversationForNotification(
    UserRealtimeNotification notification,
  ) {
    final int? relatedId = notification.relatedEntityId;
    if (relatedId == null) {
      return null;
    }

    for (final UserRealtimeConversation conversation in _realtime.conversations) {
      if (conversation.conversationId == relatedId) {
        return conversation;
      }
    }
    return null;
  }

  UserRealtimeConversation? _conversationForSenderLabel(String senderLabel) {
    final String normalized = senderLabel.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final UserRealtimeConversation conversation in _realtime.conversations) {
      if (conversation.title.trim().toLowerCase() == normalized) {
        return conversation;
      }
    }
    return null;
  }

  void _openMessageGroup(
    BuildContext context,
    UserRealtimeNotification notification,
  ) {
    final String senderLabel = _messageSenderLabel(notification);
    final UserRealtimeConversation? conversation =
        _conversationForNotification(notification) ??
        _conversationForSenderLabel(senderLabel);

    if (conversation == null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatsPage()),
      );
      return;
    }

    _realtime.openConversation(conversation.conversationId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatThreadPage(
          sellerName: conversation.title,
          lastMessage:
              conversation.lastMessageText ?? conversation.conversationType,
          sellerAvatarUrl:
              '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/'
              '${conversation.otherAccountId ?? conversation.conversationId}',
          conversationId: conversation.conversationId,
          conversationType: conversation.conversationType,
          lastMessageAt: conversation.lastMessageAt,
          isStaffParticipant: _isStaffAccountType(
            conversation.otherAccountType,
          ),
        ),
      ),
    );
  }

  bool _isStaffAccountType(String value) {
    final String normalized = value.trim().toLowerCase();
    return normalized == 'staff' ||
        normalized == 'management' ||
        normalized == 'superadmin';
  }

  String _messageSenderLabel(UserRealtimeNotification notification) {
    final String title = notification.title.trim();
    final RegExp prefixPattern = RegExp(
      r'^(new|unread)?\s*messages?\s+from\s+',
      caseSensitive: false,
    );
    final RegExp singlePrefixPattern = RegExp(
      r'^new\s+message\s+from\s+',
      caseSensitive: false,
    );

    final String cleaned = title
        .replaceFirst(prefixPattern, '')
        .replaceFirst(singlePrefixPattern, '')
        .trim();

    if (cleaned.isNotEmpty && cleaned.toLowerCase() != title.toLowerCase()) {
      return cleaned;
    }

    return cleaned.isEmpty ? 'Conversation' : cleaned;
  }

  List<_NotificationGroup> _groupNotifications(
    List<UserRealtimeNotification> notifications,
  ) {
    final Map<String, List<UserRealtimeNotification>> grouped =
        <String, List<UserRealtimeNotification>>{};

    for (final UserRealtimeNotification item in notifications) {
      final String key = _isMessageNotification(item)
          ? 'message|${item.relatedEntityType ?? ''}|${item.relatedEntityId ?? 0}|${item.title}'
          : '${item.notificationType}|${item.relatedEntityType ?? ''}|${item.relatedEntityId ?? 0}|${item.title}';
      grouped.putIfAbsent(key, () => <UserRealtimeNotification>[]).add(item);
    }

    return grouped.entries.map((_entry) {
      final List<UserRealtimeNotification> items = _entry.value
        ..sort((UserRealtimeNotification a, UserRealtimeNotification b) {
          final DateTime aTime =
              a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime bTime =
              b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      final UserRealtimeNotification latest = items.first;
      return _NotificationGroup(
        title: latest.title,
        items: List<UserRealtimeNotification>.unmodifiable(items),
      );
    }).toList(growable: false)
      ..sort((_NotificationGroup a, _NotificationGroup b) {
        final DateTime aTime =
            a.items.first.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final DateTime bTime =
            b.items.first.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
  }
}

class _NotificationGroup {
  const _NotificationGroup({
    required this.title,
    required this.items,
  });

  final String title;
  final List<UserRealtimeNotification> items;
}

class _NotificationTypeIcon extends StatelessWidget {
  const _NotificationTypeIcon({required this.notification});

  final UserRealtimeNotification notification;

  @override
  Widget build(BuildContext context) {
    final String type = notification.notificationType.toLowerCase();
    final String entity =
        (notification.relatedEntityType ?? '').toLowerCase();

    IconData icon = Icons.notifications_none;
    Color background = const Color(0xFFF3F4F6);
    Color foreground = const Color(0xFF4B5563);

    if (type.contains('message') ||
        type.contains('chat') ||
        entity.contains('message') ||
        entity.contains('conversation') ||
        entity.contains('chat')) {
      icon = Icons.chat_bubble_outline;
      background = const Color(0xFFE0F2FE);
      foreground = const Color(0xFF0369A1);
    } else if (type.contains('verification') || entity.contains('verification')) {
      icon = Icons.verified_outlined;
      background = const Color(0xFFFFF4D6);
      foreground = const Color(0xFFB7791F);
    } else if (type.contains('listing') || entity.contains('listing')) {
      icon = Icons.sell_outlined;
      background = const Color(0xFFEDE9FE);
      foreground = const Color(0xFF6D28D9);
    } else if (type.contains('seller') || entity.contains('seller')) {
      icon = Icons.storefront_outlined;
      background = const Color(0xFFDCFCE7);
      foreground = const Color(0xFF15803D);
    } else if (type.contains('warning') || type.contains('report')) {
      icon = Icons.warning_amber_rounded;
      background = const Color(0xFFFFEDD5);
      foreground = const Color(0xFFC2410C);
    }

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}
