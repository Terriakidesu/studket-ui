import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/user_realtime_service.dart';
import 'chat_message_text.dart';
import 'chat_thread_page.dart';
import 'components/account_avatar.dart';
import 'components/studket_app_bar.dart';
import 'seller_profile_page.dart';

export 'chat_thread_page.dart' show ChatThreadPage, InquiryProductData;

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  Map<int, _ApiMessage> _latestMessagesByConversation =
      <int, _ApiMessage>{};
  int _lastRealtimeConversationCount = 0;
  int _lastRealtimeNotificationCount = 0;
  int _lastRealtimeNewMessageCount = 0;
  bool _isReloadingPreviews = false;

  void _openOtherUserProfile({
    required String name,
    required String avatarUrl,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SellerProfilePage(
          sellerName: name,
          sellerAvatarUrl: avatarUrl,
          sellerRating: 4.5,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _realtime.addListener(_handleRealtimeChanged);
    unawaited(_realtime.ensureConnected());
    unawaited(_loadConversationPreviews());
  }

  @override
  void dispose() {
    _realtime.removeListener(_handleRealtimeChanged);
    super.dispose();
  }

  void _handleRealtimeChanged() {
    final int conversationCount = _realtime.conversations.length;
    final int notificationCount = _realtime.notifications.length;
    final int newMessageCount = _realtime.newMessageConversationCount;
    final bool shouldReload =
        conversationCount != _lastRealtimeConversationCount ||
        notificationCount != _lastRealtimeNotificationCount ||
        newMessageCount != _lastRealtimeNewMessageCount;
    _lastRealtimeConversationCount = conversationCount;
    _lastRealtimeNotificationCount = notificationCount;
    _lastRealtimeNewMessageCount = newMessageCount;
    if (shouldReload) {
      unawaited(_loadConversationPreviews());
    }
  }

  Future<void> _loadConversationPreviews() async {
    if (_isReloadingPreviews) {
      return;
    }
    _isReloadingPreviews = true;
    try {
      final http.Response response = await http
          .get(
            ApiRoutes.messages(),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return;
      }

      final Map<int, _ApiMessage> latestByConversation = <int, _ApiMessage>{};
      for (final MapEntry<int, Map<dynamic, dynamic>> entry
          in decoded.whereType<Map>().toList(growable: false).asMap().entries) {
        final _ApiMessage message = _ApiMessage.fromJson(
          Map<String, dynamic>.from(entry.value),
          sourceOrder: entry.key,
        );
        final _ApiMessage? existing = latestByConversation[message.conversationId];
        if (existing == null ||
            message.sentAt.isAfter(existing.sentAt) ||
            (message.sentAt.isAtSameMomentAs(existing.sentAt) &&
                message.sourceOrder > existing.sourceOrder)) {
          latestByConversation[message.conversationId] = message;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _latestMessagesByConversation = latestByConversation;
      });
    } catch (_) {
    } finally {
      _isReloadingPreviews = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const StudketAppBar(title: 'Chats'),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          final List<UserRealtimeConversation> conversations =
              _visibleConversations();
          if (conversations.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _realtime.isConnected
                      ? 'No websocket conversations were returned for this user.'
                      : (_realtime.error ??
                            'Connect the user websocket to load conversations.'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: conversations.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: colorScheme.outlineVariant),
            itemBuilder: (BuildContext context, int index) {
              final UserRealtimeConversation conversation = conversations[index];
              final int avatarAccountId =
                  conversation.otherAccountId ?? conversation.conversationId;
              final bool hasNewMessage = _realtime.hasNewMessage(
                conversation.conversationId,
              );
              final UserRealtimeTypingState? typingState =
                  _realtime.typingStateFor(conversation.conversationId);
              final bool isTyping = typingState?.isTyping == true;
              final String recentMessage = isTyping
                  ? '${typingState!.username} is typing...'
                  : _recentMessagePreview(conversation);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: hasNewMessage
                      ? Theme.of(context).colorScheme.primary.withValues(
                          alpha: 0.10,
                        )
                      : Colors.transparent,
                  border: Border(
                    left: BorderSide(
                      color: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                      width: 4,
                    ),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () {
                      _openOtherUserProfile(
                        name: conversation.title,
                        avatarUrl: _avatarUrlForConversation(conversation),
                      );
                    },
                    child: AccountAvatar(
                      accountId: avatarAccountId,
                      radius: 20,
                      backgroundColor: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      label: conversation.title,
                    ),
                  ),
                  title: Text(
                    conversation.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    recentMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isTyping
                          ? Theme.of(context).colorScheme.primary
                           : (hasNewMessage
                               ? colorScheme.onSurface
                               : colorScheme.onSurfaceVariant),
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                      fontWeight: hasNewMessage || isTyping
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: hasNewMessage
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    _realtime.openConversation(conversation.conversationId);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatThreadPage(
                          sellerName: conversation.title,
                          lastMessage: conversation.conversationType,
                          sellerAvatarUrl: _avatarUrlForConversation(
                            conversation,
                          ),
                          conversationId: conversation.conversationId,
                          conversationType: conversation.conversationType,
                          lastMessageAt: conversation.lastMessageAt,
                          isStaffParticipant: _isStaffAccountType(
                            conversation.otherAccountType,
                          ),
                        ),
                      ),
                    );
                    if (!mounted) {
                      return;
                    }
                    await _loadConversationPreviews();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  String _avatarUrlForConversation(UserRealtimeConversation conversation) {
    final int accountId =
        conversation.otherAccountId ?? conversation.conversationId;
    return '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/$accountId';
  }

  String _recentMessagePreview(UserRealtimeConversation conversation) {
    final List<UserRealtimeMessage> liveMessages = _realtime.messagesFor(
      conversation.conversationId,
    );
    if (liveMessages.isNotEmpty) {
      return _previewTextForMessage(liveMessages.last.messageText);
    }

    final String? apiPreview =
        _latestMessagesByConversation[conversation.conversationId]
            ?.messageText
            .trim();
    if (apiPreview != null && apiPreview.isNotEmpty) {
      return _previewTextForMessage(apiPreview);
    }

    final String? preview = conversation.lastMessageText?.trim();
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }

    return _formatConversationType(conversation.conversationType);
  }

  String _previewTextForMessage(String messageText) {
    return formatChatMessagePreview(messageText);
  }

  String _formatConversationType(String conversationType) {
    if (conversationType.trim().isEmpty) {
      return 'Conversation';
    }
    return conversationType
        .split('_')
        .where((String segment) => segment.trim().isNotEmpty)
        .map(
          (String segment) =>
              '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  bool _isStaffAccountType(String? accountType) {
    final String normalized = (accountType ?? '').trim().toLowerCase();
    return normalized == 'staff' ||
        normalized == 'management' ||
        normalized == 'superadmin';
  }

  List<UserRealtimeConversation> _visibleConversations() {
    final List<UserRealtimeConversation> merged =
        List<UserRealtimeConversation>.from(_realtime.conversations);
    final Set<int> knownIds = merged
        .map((UserRealtimeConversation item) => item.conversationId)
        .toSet();
    _latestMessagesByConversation.forEach((int conversationId, _ApiMessage message) {
      if (knownIds.contains(conversationId)) {
        return;
      }
      final bool isMine =
          message.senderId != null && message.senderId == ApiAuthSession.accountId;
      merged.add(
        UserRealtimeConversation(
          conversationId: conversationId,
          conversationType: 'conversation',
          otherAccountId: isMine ? null : message.senderId,
          otherUsername: isMine
              ? 'Conversation'
              : (message.senderUsername?.trim().isNotEmpty == true
                  ? message.senderUsername!.trim()
                  : 'Conversation'),
          otherAccountType: 'user',
          lastMessageText: message.messageText,
          lastMessageAt: message.sentAt,
          messageCount: 1,
        ),
      );
    });
    merged.sort(_compareConversationsByLatest);
    return merged;
  }

  int _compareConversationsByLatest(
    UserRealtimeConversation a,
    UserRealtimeConversation b,
  ) {
    final DateTime aTime =
        a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final DateTime bTime =
        b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final int byTime = bTime.compareTo(aTime);
    if (byTime != 0) {
      return byTime;
    }
    return b.conversationId.compareTo(a.conversationId);
  }
}

class _ApiMessage {
  const _ApiMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.messageText,
    required this.sentAt,
    required this.sourceOrder,
  });

  final int messageId;
  final int conversationId;
  final int? senderId;
  final String? senderUsername;
  final String messageText;
  final DateTime sentAt;
  final int sourceOrder;

  factory _ApiMessage.fromJson(
    Map<String, dynamic> json, {
    required int sourceOrder,
  }) {
    final DateTime parsedSentAt =
        DateTime.tryParse((json['sent_at'] ?? '').toString())?.toLocal() ??
        DateTime.now();
    return _ApiMessage(
      messageId: (json['message_id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num?)?.toInt(),
      senderUsername: (json['sender_username'] ?? '').toString().trim(),
      messageText: (json['message_text'] ?? '').toString(),
      sentAt: parsedSentAt,
      sourceOrder: sourceOrder,
    );
  }
}
