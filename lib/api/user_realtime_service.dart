import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_notifications.dart';
import 'api_auth_session.dart';
import 'api_base_url.dart';

class UserRealtimeConversation {
  const UserRealtimeConversation({
    required this.conversationId,
    required this.conversationType,
    required this.otherAccountId,
    required this.otherUsername,
    required this.otherAccountType,
    this.lastMessageText,
    this.lastMessageAt,
    this.messageCount = 0,
  });

  final int conversationId;
  final String conversationType;
  final int? otherAccountId;
  final String otherUsername;
  final String otherAccountType;
  final String? lastMessageText;
  final DateTime? lastMessageAt;
  final int messageCount;

  String get title => otherUsername.isEmpty ? 'Conversation' : otherUsername;

  UserRealtimeConversation copyWith({
    String? lastMessageText,
    DateTime? lastMessageAt,
    int? messageCount,
  }) {
    return UserRealtimeConversation(
      conversationId: conversationId,
      conversationType: conversationType,
      otherAccountId: otherAccountId,
      otherUsername: otherUsername,
      otherAccountType: otherAccountType,
      lastMessageText: lastMessageText ?? this.lastMessageText,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  factory UserRealtimeConversation.fromJson(Map<String, dynamic> json) {
    return UserRealtimeConversation(
      conversationId: _asInt(json['conversation_id']) ?? 0,
      conversationType: _asString(json['conversation_type'], 'conversation'),
      otherAccountId: _asInt(json['other_account_id']),
      otherUsername: _asString(json['other_username'], 'Conversation'),
      otherAccountType: _asString(json['other_account_type'], 'user'),
      lastMessageText:
          _asNullableString(json['last_message_text']) ??
          _asNullableString(json['last_message']) ??
          _asNullableString(json['latest_message_text']) ??
          _asNullableString(json['latest_message']),
      lastMessageAt: _asDateTime(json['last_message_at']),
      messageCount: _asInt(json['message_count']) ?? 0,
    );
  }
}

class UserRealtimeNotification {
  const UserRealtimeNotification({
    required this.notificationId,
    required this.notificationType,
    required this.title,
    required this.body,
    required this.isRead,
    this.relatedEntityType,
    this.relatedEntityId,
    this.readAt,
    this.createdAt,
  });

  final int notificationId;
  final String notificationType;
  final String title;
  final String body;
  final bool isRead;
  final String? relatedEntityType;
  final int? relatedEntityId;
  final DateTime? readAt;
  final DateTime? createdAt;

  UserRealtimeNotification copyWith({
    bool? isRead,
    DateTime? readAt,
  }) {
    return UserRealtimeNotification(
      notificationId: notificationId,
      notificationType: notificationType,
      title: title,
      body: body,
      isRead: isRead ?? this.isRead,
      relatedEntityType: relatedEntityType,
      relatedEntityId: relatedEntityId,
      readAt: readAt ?? this.readAt,
      createdAt: createdAt,
    );
  }

  factory UserRealtimeNotification.fromJson(Map<String, dynamic> json) {
    return UserRealtimeNotification(
      notificationId: _asInt(json['notification_id']) ?? 0,
      notificationType: _asString(
        json['notification_type'],
        'notification',
      ),
      title: _asString(json['title'], 'Notification'),
      body: _asString(json['body'], ''),
      isRead: json['is_read'] == true,
      relatedEntityType: json['related_entity_type']?.toString(),
      relatedEntityId: _asInt(json['related_entity_id']),
      readAt: _asDateTime(json['read_at']),
      createdAt: _asDateTime(json['created_at']),
    );
  }
}

class UserRealtimeMessage {
  const UserRealtimeMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderUsername,
    required this.messageText,
    required this.isRead,
    required this.sentAt,
    required this.receivedSequence,
  });

  final int messageId;
  final int conversationId;
  final int? senderId;
  final String senderUsername;
  final String messageText;
  final bool isRead;
  final DateTime? sentAt;
  final int receivedSequence;

  bool get isMine => senderId != null && senderId == ApiAuthSession.accountId;

  factory UserRealtimeMessage.fromJson(
    Map<String, dynamic> json, {
    required int receivedSequence,
  }) {
    return UserRealtimeMessage(
      messageId: _asInt(json['message_id']) ?? 0,
      conversationId: _asInt(json['conversation_id']) ?? 0,
      senderId: _asInt(json['sender_id']),
      senderUsername: _asString(json['sender_username'], 'Unknown'),
      messageText: _asString(json['message_text'], ''),
      isRead: json['is_read'] == true,
      sentAt: _asDateTime(json['sent_at']),
      receivedSequence: receivedSequence,
    );
  }
}

class UserRealtimeTypingState {
  const UserRealtimeTypingState({
    required this.conversationId,
    required this.accountId,
    required this.username,
    required this.accountType,
    required this.isTyping,
  });

  final int conversationId;
  final int? accountId;
  final String username;
  final String accountType;
  final bool isTyping;

  bool get isMine => accountId != null && accountId == ApiAuthSession.accountId;

  factory UserRealtimeTypingState.fromJson(Map<String, dynamic> json) {
    return UserRealtimeTypingState(
      conversationId: _asInt(json['conversation_id']) ?? 0,
      accountId: _asInt(json['account_id']),
      username: _asString(json['username'], 'Someone'),
      accountType: _asString(json['account_type'], 'user'),
      isTyping: json['is_typing'] == true,
    );
  }
}

class UserRealtimeService extends ChangeNotifier {
  UserRealtimeService._();

  static final UserRealtimeService instance = UserRealtimeService._();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int? _connectedAccountId;
  bool _isConnecting = false;
  bool _isConnected = false;
  String? _error;
  DateTime? _lastPongAt;
  final List<UserRealtimeConversation> _conversations =
      <UserRealtimeConversation>[];
  final List<UserRealtimeNotification> _notifications =
      <UserRealtimeNotification>[];
  final Map<int, List<UserRealtimeMessage>> _messages =
      <int, List<UserRealtimeMessage>>{};
  final Map<int, UserRealtimeTypingState> _typingStates =
      <int, UserRealtimeTypingState>{};
  final Set<int> _conversationsWithNewMessages = <int>{};
  int _messageSequence = 0;
  int? _activeConversationId;

  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  String? get error => _error;
  DateTime? get lastPongAt => _lastPongAt;
  List<UserRealtimeConversation> get conversations =>
      List<UserRealtimeConversation>.unmodifiable(_conversations);
  List<UserRealtimeNotification> get notifications =>
      List<UserRealtimeNotification>.unmodifiable(_notifications);
  int get newMessageConversationCount => _conversationsWithNewMessages.length;

  List<UserRealtimeMessage> messagesFor(int conversationId) {
    return List<UserRealtimeMessage>.unmodifiable(
      _messages[conversationId] ?? const <UserRealtimeMessage>[],
    );
  }

  bool hasNewMessage(int conversationId) {
    return _conversationsWithNewMessages.contains(conversationId);
  }

  UserRealtimeTypingState? typingStateFor(int conversationId) {
    return _typingStates[conversationId];
  }

  void openConversation(int conversationId) {
    _activeConversationId = conversationId;
    final bool removed = _conversationsWithNewMessages.remove(conversationId);
    if (removed) {
      notifyListeners();
    }
  }

  void closeConversation(int conversationId) {
    if (_activeConversationId == conversationId) {
      _activeConversationId = null;
    }
  }

  Future<void> ensureConnected() async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      _setError('Connect after login to use realtime user endpoints.');
      return;
    }

    if (_isConnected && _connectedAccountId == accountId) {
      return;
    }

    await connect(accountId: accountId);
  }

  Future<void> connect({required int accountId}) async {
    await disconnect(clearState: true);
    _isConnecting = true;
    _error = null;
    notifyListeners();

    try {
      final String url =
          '${resolveWebSocketBaseUrl()}/ws/users/$accountId';
      _socket = await WebSocket.connect(url);
      _connectedAccountId = accountId;
      _isConnecting = false;
      _isConnected = true;
      notifyListeners();

      _subscription = _socket!.listen(
        _handleRawMessage,
        onError: (Object error) {
          _setError(error.toString());
        },
        onDone: () {
          _isConnected = false;
          notifyListeners();
        },
        cancelOnError: false,
      );
    } catch (error) {
      _setError('Realtime connection failed: $error');
      _isConnecting = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  Future<void> disconnect({bool clearState = false}) async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _isConnected = false;
    _isConnecting = false;
    if (clearState) {
      _conversations.clear();
      _notifications.clear();
      _messages.clear();
      _typingStates.clear();
      _conversationsWithNewMessages.clear();
      _messageSequence = 0;
      _activeConversationId = null;
      _connectedAccountId = null;
      _lastPongAt = null;
      _error = null;
    }
    notifyListeners();
  }

  Future<void> sendPing() async {
    await _send(<String, dynamic>{'action': 'ping'});
  }

  Future<void> subscribeConversation(int conversationId) async {
    await _send(<String, dynamic>{
      'action': 'subscribe_conversation',
      'conversation_id': conversationId,
    });
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _send(<String, dynamic>{
      'action': 'mark_notification_read',
      'notification_id': notificationId,
    });
  }

  Future<void> markAllNotificationsRead() async {
    final List<int> unreadIds = _notifications
        .where((UserRealtimeNotification item) => !item.isRead)
        .map((UserRealtimeNotification item) => item.notificationId)
        .toList(growable: false);
    for (final int notificationId in unreadIds) {
      await markNotificationRead(notificationId);
    }
  }

  Future<void> sendTypingStatus({
    required int conversationId,
    required bool isTyping,
  }) async {
    await _send(<String, dynamic>{
      'action': 'typing_status',
      'conversation_id': conversationId,
      'is_typing': isTyping,
    });
  }

  Future<void> sendMessage({
    required int conversationId,
    required String messageText,
  }) async {
    await _send(<String, dynamic>{
      'action': 'send_message',
      'conversation_id': conversationId,
      'message_text': messageText,
    });
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    if (_socket == null || !_isConnected) {
      _setError('Realtime socket is not connected.');
      return;
    }
    _socket!.add(jsonEncode(payload));
  }

  void _handleRawMessage(dynamic data) {
    final dynamic decoded = jsonDecode(data.toString());
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    switch (decoded['type']) {
      case 'bootstrap':
        _handleBootstrap(decoded);
        return;
      case 'pong':
        _lastPongAt = DateTime.now();
        notifyListeners();
        return;
      case 'chat.message':
        final dynamic messageJson = decoded['message'];
        if (messageJson is Map<String, dynamic>) {
          final UserRealtimeMessage message = UserRealtimeMessage.fromJson(
            messageJson,
            receivedSequence: ++_messageSequence,
          );
          _addMessage(message);
          if (!message.isMine && _activeConversationId != message.conversationId) {
            AppNotifications.instance.showIncomingMessage(
              messageId: message.messageId,
              conversationId: message.conversationId,
              senderName: message.senderUsername,
              messageText: message.messageText,
            );
          }
        }
        return;
      case 'chat.typing':
        _updateTypingState(UserRealtimeTypingState.fromJson(decoded));
        return;
      case 'notification.created':
        final dynamic notificationJson = decoded['notification'];
        if (notificationJson is Map<String, dynamic>) {
          final UserRealtimeNotification notification =
              UserRealtimeNotification.fromJson(notificationJson);
          _notifications.removeWhere(
            (UserRealtimeNotification item) =>
                item.notificationId ==
                (_asInt(notificationJson['notification_id']) ?? -1),
          );
          _notifications.insert(
            0,
            notification,
          );
          if (!notification.isRead && !_isMessageNotification(notification)) {
            AppNotifications.instance.showRealtimeNotification(
              notificationId: notification.notificationId,
              title: notification.title,
              body: notification.body,
            );
          }
          notifyListeners();
        }
        return;
      case 'notification.updated':
        final dynamic notificationJson = decoded['notification'];
        if (notificationJson is Map<String, dynamic>) {
          _updateNotification(UserRealtimeNotification.fromJson(notificationJson));
        }
        return;
      case 'error':
        _setError(_asString(decoded['detail'], 'Unsupported action'));
        return;
    }
  }

  void _handleBootstrap(Map<String, dynamic> decoded) {
    final dynamic conversationsJson = decoded['conversations'];
    final dynamic notificationsJson = decoded['notifications'];

    _conversations
      ..clear()
      ..addAll(
        (conversationsJson is List ? conversationsJson : const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(UserRealtimeConversation.fromJson),
      );
    _conversations.sort(_compareConversationsByLatest);

    _notifications
      ..clear()
      ..addAll(
        (notificationsJson is List ? notificationsJson : const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(UserRealtimeNotification.fromJson),
      );
    _typingStates.clear();

    notifyListeners();
  }

  void _addMessage(UserRealtimeMessage message) {
    final List<UserRealtimeMessage> items =
        _messages.putIfAbsent(
          message.conversationId,
          () => <UserRealtimeMessage>[],
        );
    items.add(message);

    final int conversationIndex = _conversations.indexWhere(
      (UserRealtimeConversation item) =>
          item.conversationId == message.conversationId,
    );
    if (conversationIndex >= 0) {
      final UserRealtimeConversation updated = _conversations[conversationIndex]
          .copyWith(
            lastMessageText: message.messageText,
            lastMessageAt: message.sentAt,
            messageCount: _conversations[conversationIndex].messageCount + 1,
          );
      _conversations
        ..removeAt(conversationIndex)
        ..insert(0, updated);
    }

    if (!message.isMine && _activeConversationId != message.conversationId) {
      _conversationsWithNewMessages.add(message.conversationId);
    }

    notifyListeners();
  }

  void _updateNotification(UserRealtimeNotification notification) {
    final int index = _notifications.indexWhere(
      (UserRealtimeNotification item) =>
          item.notificationId == notification.notificationId,
    );
    if (index < 0) {
      _notifications.insert(0, notification);
    } else {
      _notifications[index] = notification;
    }
    notifyListeners();
  }

  void _updateTypingState(UserRealtimeTypingState state) {
    if (state.isMine) {
      return;
    }
    if (!state.isTyping) {
      if (_typingStates.remove(state.conversationId) != null) {
        notifyListeners();
      }
      return;
    }
    _typingStates[state.conversationId] = state;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  bool _isMessageNotification(UserRealtimeNotification notification) {
    final String type = notification.notificationType.trim().toLowerCase();
    final String? entityType = notification.relatedEntityType
        ?.trim()
        .toLowerCase();
    return type.contains('message') ||
        type.contains('chat') ||
        entityType == 'message' ||
        entityType == 'conversation';
  }
}

int _compareConversationsByLatest(
  UserRealtimeConversation a,
  UserRealtimeConversation b,
) {
  final DateTime aTime = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final DateTime bTime = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bTime.compareTo(aTime);
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String _asString(dynamic value, String fallback) {
  final String text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

String? _asNullableString(dynamic value) {
  final String text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

DateTime? _asDateTime(dynamic value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}
