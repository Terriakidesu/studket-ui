import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/user_realtime_service.dart';
import 'components/studket_app_bar.dart';
import 'seller_profile_page.dart';

class ChatsPage extends StatefulWidget {
  const ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  Map<int, _ApiMessage> _latestMessagesByConversation =
      <int, _ApiMessage>{};

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
    unawaited(_realtime.ensureConnected());
    unawaited(_loadConversationPreviews());
  }

  Future<void> _loadConversationPreviews() async {
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StudketAppBar(title: 'Chats'),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          if (_realtime.conversations.isEmpty) {
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
            itemCount: _realtime.conversations.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Colors.grey[200]),
            itemBuilder: (BuildContext context, int index) {
              final UserRealtimeConversation conversation =
                  _realtime.conversations[index];
              final String avatarUrl = _avatarUrlForConversation(conversation);
              final bool hasNewMessage = _realtime.hasNewMessage(
                conversation.conversationId,
              );
              final String recentMessage = _recentMessagePreview(conversation);
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
                        avatarUrl: avatarUrl,
                      );
                    },
                    child: CircleAvatar(
                      backgroundColor: hasNewMessage
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      backgroundImage: NetworkImage(avatarUrl),
                      child: conversation.title.isEmpty
                          ? const Text('?')
                          : null,
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
                      color: hasNewMessage ? Colors.black87 : Colors.grey[700],
                      fontWeight: hasNewMessage
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
                          sellerAvatarUrl: avatarUrl,
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
    final int seed = conversation.otherAccountId ?? conversation.conversationId;
    return 'https://i.pravatar.cc/150?img=${(seed % 70) + 1}';
  }

  String _recentMessagePreview(UserRealtimeConversation conversation) {
    final List<UserRealtimeMessage> liveMessages = _realtime.messagesFor(
      conversation.conversationId,
    );
    if (liveMessages.isNotEmpty) {
      return liveMessages.last.messageText.trim();
    }

    final String? apiPreview =
        _latestMessagesByConversation[conversation.conversationId]
            ?.messageText
            .trim();
    if (apiPreview != null && apiPreview.isNotEmpty) {
      return apiPreview;
    }

    final String? preview = conversation.lastMessageText?.trim();
    if (preview != null && preview.isNotEmpty) {
      return preview;
    }

    return _formatConversationType(conversation.conversationType);
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
}

class ChatThreadPage extends StatefulWidget {
  const ChatThreadPage({
    super.key,
    required this.sellerName,
    required this.lastMessage,
    required this.sellerAvatarUrl,
    this.inquiryProduct,
    this.conversationId,
    this.conversationType,
    this.lastMessageAt,
    this.isStaffParticipant = false,
  });

  final String sellerName;
  final String lastMessage;
  final String sellerAvatarUrl;
  final InquiryProductData? inquiryProduct;
  final int? conversationId;
  final String? conversationType;
  final DateTime? lastMessageAt;
  final bool isStaffParticipant;

  @override
  State<ChatThreadPage> createState() => _ChatThreadPageState();
}

class _ChatThreadPageState extends State<ChatThreadPage> {
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoadingHistory = false;
  String? _historyError;
  List<_ApiMessage> _historyMessages = const <_ApiMessage>[];
  int _lastRenderedMessageCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_realtime.ensureConnected());
    if (widget.conversationId != null) {
      _realtime.openConversation(widget.conversationId!);
      unawaited(_realtime.subscribeConversation(widget.conversationId!));
      unawaited(_loadHistory(widget.conversationId!));
    }
  }

  @override
  void dispose() {
    if (widget.conversationId != null) {
      _realtime.closeConversation(widget.conversationId!);
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory(int conversationId) async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

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
        throw HttpException(_extractErrorMessage(response));
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Messages response must be a list.');
      }

      final List<_ApiMessage> parsed = decoded
          .whereType<Map>()
          .toList(growable: false)
          .asMap()
          .entries
          .map(
            (MapEntry<int, Map<dynamic, dynamic>> entry) => _ApiMessage.fromJson(
              Map<String, dynamic>.from(entry.value),
              sourceOrder: entry.key,
            ),
          )
          .where(
            (_ApiMessage item) => item.conversationId == conversationId,
          )
          .toList(growable: false)
        ..sort((_ApiMessage a, _ApiMessage b) => a.sentAt.compareTo(b.sentAt));

      if (!mounted) return;
      setState(() {
        _historyMessages = parsed;
      });
      _scheduleScrollToBottom(jump: true);
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _historyError = 'Loading previous messages timed out.';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _historyError = 'Could not connect to the messages endpoint.';
      });
    } on HttpException catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error.message;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _historyError = 'Messages endpoint returned an invalid response.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _historyError = 'Failed to load previous messages.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
        });
      }
    }
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is Map<String, dynamic>) {
          final dynamic error = detail['error'];
          if (error is String && error.trim().isNotEmpty) {
            return error.trim();
          }
        }
      }
    } catch (_) {}
    return 'Messages request failed (HTTP ${response.statusCode}).';
  }

  Future<void> _sendMessage() async {
    final int? conversationId = widget.conversationId;
    final String text = _messageController.text.trim();
    if (conversationId == null || text.isEmpty) {
      return;
    }

    await _realtime.sendMessage(
      conversationId: conversationId,
      messageText: text,
    );
    _messageController.clear();
    _scheduleScrollToBottom();
  }

  List<_TimelineMessage> _buildTimeline(int conversationId) {
    final Map<String, _TimelineMessage> items = <String, _TimelineMessage>{};

    for (final _ApiMessage message in _historyMessages) {
      items['api:${message.messageId}'] = _TimelineMessage.api(message);
    }
    for (final UserRealtimeMessage message
        in _realtime.messagesFor(conversationId)) {
      final String key = message.messageId > 0
          ? 'api:${message.messageId}'
          : 'rt:${message.conversationId}:${message.senderUsername}:${message.sentAt?.toIso8601String()}:${message.messageText}';
      items[key] = _TimelineMessage.realtime(message);
    }

    final List<_TimelineMessage> timeline = items.values.toList(growable: false)
      ..sort((_TimelineMessage a, _TimelineMessage b) {
        if (a.isRealtime != b.isRealtime) {
          return a.isRealtime ? 1 : -1;
        }
        if (a.isRealtime && b.isRealtime) {
          return a.sortOrder.compareTo(b.sortOrder);
        }
        final int byDate = a.sentAt.compareTo(b.sentAt);
        if (byDate != 0) {
          return byDate;
        }
        final int byId = a.messageId.compareTo(b.messageId);
        if (byId != 0) {
          return byId;
        }
        return a.sortOrder.compareTo(b.sortOrder);
      });
    return timeline;
  }

  void _scheduleScrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      final double target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
        return;
      }
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final int? conversationId = widget.conversationId;

    return Scaffold(
      appBar: StudketAppBar(
        title: widget.sellerName,
        actions: [
          IconButton(
            tooltip: 'View profile',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SellerProfilePage(
                    sellerName: widget.sellerName,
                    sellerAvatarUrl: widget.sellerAvatarUrl,
                    sellerRating: 4.5,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _realtime,
        builder: (BuildContext context, _) {
          if (conversationId == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Starting a brand new conversation is not documented as a public user endpoint yet. Existing websocket conversations are available from the Chats screen.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final List<_TimelineMessage> timeline = _buildTimeline(conversationId);
          if (timeline.length != _lastRenderedMessageCount) {
            _lastRenderedMessageCount = timeline.length;
            _scheduleScrollToBottom(
              jump: timeline.length <= 1 || _isLoadingHistory,
            );
          }

          return Column(
            children: [
              Expanded(
                child: _isLoadingHistory
                    ? const Center(child: CircularProgressIndicator())
                    : _historyError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _historyError!,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : timeline.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            'No previous messages were returned from `api/v1/messages/` for this conversation.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: timeline.length,
                        itemBuilder: (BuildContext context, int index) {
                          final _TimelineMessage message = timeline[index];
                          final _TimelineMessage? previous = index > 0
                              ? timeline[index - 1]
                              : null;
                          final bool startsNewGroup =
                              previous == null || previous.isMine != message.isMine;
                          return Align(
                            alignment: message.isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: EdgeInsets.only(
                                top: startsNewGroup ? 12 : 2,
                                bottom: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: message.isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (startsNewGroup)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 4,
                                        right: 4,
                                        bottom: 4,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            message.senderName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Colors.grey[600],
                                                ),
                                          ),
                                          if (!message.isMine &&
                                              widget.isStaffParticipant) ...[
                                            const SizedBox(width: 6),
                                            const _InlineStaffBadge(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: message.isMine
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      message.text,
                                      style: TextStyle(
                                        color: message.isMine
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatMessageMeta(message.sentAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Type a message',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatMessageMeta(DateTime sentAt) {
    final DateTime local = sentAt.toLocal();
    final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _InlineStaffBadge extends StatelessWidget {
  const _InlineStaffBadge();

  @override
  Widget build(BuildContext context) {
    final Color foregroundColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: foregroundColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foregroundColor.withValues(alpha: 0.32)),
      ),
      child: Text(
        'Staff',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }
}

class InquiryProductData {
  const InquiryProductData({
    required this.name,
    required this.location,
    required this.imageUrl,
  });

  final String name;
  final String location;
  final String imageUrl;
}

class _ApiMessage {
  const _ApiMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.messageText,
    required this.sentAt,
    required this.sourceOrder,
  });

  final int messageId;
  final int conversationId;
  final int? senderId;
  final String messageText;
  final DateTime sentAt;
  final int sourceOrder;

  factory _ApiMessage.fromJson(Map<String, dynamic> json, {required int sourceOrder}) {
    final DateTime parsedSentAt =
        DateTime.tryParse((json['sent_at'] ?? '').toString())?.toLocal() ??
        DateTime.now();
    return _ApiMessage(
      messageId: (json['message_id'] as num?)?.toInt() ?? 0,
      conversationId: (json['conversation_id'] as num?)?.toInt() ?? 0,
      senderId: (json['sender_id'] as num?)?.toInt(),
      messageText: (json['message_text'] ?? '').toString(),
      sentAt: parsedSentAt,
      sourceOrder: sourceOrder,
    );
  }
}

class _TimelineMessage {
  const _TimelineMessage({
    required this.messageId,
    required this.text,
    required this.isMine,
    required this.isRealtime,
    required this.senderName,
    required this.sentAt,
    required this.sortOrder,
  });

  final int messageId;
  final String text;
  final bool isMine;
  final bool isRealtime;
  final String senderName;
  final DateTime sentAt;
  final int sortOrder;

  factory _TimelineMessage.api(_ApiMessage message) {
    final bool isMine =
        message.senderId != null && message.senderId == ApiAuthSession.accountId;
    return _TimelineMessage(
      messageId: message.messageId,
      text: message.messageText,
      isMine: isMine,
      isRealtime: false,
      senderName: isMine ? 'You' : 'Account ${message.senderId ?? '-'}',
      sentAt: message.sentAt,
      sortOrder: message.sourceOrder,
    );
  }

  factory _TimelineMessage.realtime(UserRealtimeMessage message) {
    return _TimelineMessage(
      messageId: message.messageId,
      text: message.messageText,
      isMine: message.isMine,
      isRealtime: true,
      senderName: message.senderUsername,
      sentAt: message.sentAt ?? DateTime.now(),
      sortOrder: message.receivedSequence,
    );
  }
}
