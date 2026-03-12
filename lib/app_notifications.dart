import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/user_realtime_service.dart';
import 'app_navigation.dart';
import 'chats_page.dart';
import 'chat_message_text.dart';
import 'product_details_page.dart';
import 'user_profile_page.dart';

class AppNotifications {
  AppNotifications._();

  static final AppNotifications instance = AppNotifications._();

  static const String _messagesChannelId = 'studket_messages';
  static const String _notificationsChannelId = 'studket_notifications';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _recentNotifications = <String, DateTime>{};
  String? _pendingPayload;
  bool _isHandlingNavigation = false;

  bool _isInitialized = false;
  static const Duration _dedupeWindow = Duration(seconds: 8);

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwinSettings =
        DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      ),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String payload = (response.payload ?? '').trim();
        if (payload.isEmpty) {
          return;
        }
        _pendingPayload = payload;
        unawaited(handlePendingNavigation());
      },
    );

    final NotificationAppLaunchDetails? launchDetails =
        await _plugin.getNotificationAppLaunchDetails();
    final String launchedPayload =
        (launchDetails?.notificationResponse?.payload ?? '').trim();
    if (launchedPayload.isNotEmpty) {
      _pendingPayload = launchedPayload;
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _messagesChannelId,
            'Messages',
            description: 'Incoming Studket chat messages',
            importance: Importance.high,
          ),
        );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _notificationsChannelId,
            'Notifications',
            description: 'Studket account notifications',
            importance: Importance.high,
          ),
        );

    _isInitialized = true;
  }

  Future<void> showIncomingMessage({
    required int messageId,
    required int conversationId,
    required String senderName,
    required String messageText,
    int? senderAccountId,
  }) async {
    if (!_isInitialized) {
      return;
    }

    if (_shouldSkipDuplicate('message:$messageId')) {
      return;
    }

    final ByteArrayAndroidIcon? senderIcon = senderAccountId == null
        ? null
        : await _loadProfileIcon(senderAccountId);
    final Person senderPerson = Person(
      name: senderName,
      key: senderAccountId?.toString() ?? senderName,
      important: true,
      icon: senderIcon,
    );
    const Person me = Person(name: 'You');

    await _plugin.show(
      100000 + conversationId,
      senderName,
      formatChatMessagePreview(messageText),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _messagesChannelId,
          'Messages',
          channelDescription: 'Incoming Studket chat messages',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          styleInformation: MessagingStyleInformation(
            me,
            conversationTitle: senderName,
            groupConversation: false,
              messages: <Message>[
                Message(
                  formatChatMessagePreview(messageText),
                  DateTime.now(),
                  senderPerson,
                ),
            ],
          ),
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(<String, dynamic>{
        'kind': 'message',
        'conversation_id': conversationId,
        'sender_name': senderName,
        'sender_account_id': senderAccountId,
      }),
    );
  }

  Future<void> showRealtimeNotification({
    required int notificationId,
    required String notificationType,
    required String title,
    required String body,
    String? relatedEntityType,
    int? relatedEntityId,
  }) async {
    if (!_isInitialized) {
      return;
    }

    if (_shouldSkipDuplicate('notification:$notificationId')) {
      return;
    }

    await _plugin.show(
      200000 + notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _notificationsChannelId,
          'Notifications',
          channelDescription: 'Studket account notifications',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(<String, dynamic>{
        'kind': 'notification',
        'notification_id': notificationId,
        'notification_type': notificationType,
        'title': title,
        'body': body,
        'related_entity_type':
            (relatedEntityType ?? '').trim().isEmpty ? null : relatedEntityType,
        'related_entity_id': relatedEntityId,
      }),
    );
  }

  Future<void> handlePendingNavigation() async {
    final String payload = (_pendingPayload ?? '').trim();
    if (payload.isEmpty || _isHandlingNavigation || ApiAuthSession.accountId == null) {
      return;
    }
    final NavigatorState? navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    _isHandlingNavigation = true;
    _pendingPayload = null;
    try {
      final dynamic decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) {
        return;
      }
      final UserRealtimeService realtime = UserRealtimeService.instance;
      await realtime.ensureConnected();
      final String kind = (decoded['kind'] ?? '').toString().trim().toLowerCase();
      if (kind == 'message') {
        await _openMessagePayload(decoded, navigator, realtime);
        return;
      }
      if (kind == 'notification') {
        await _openNotificationPayload(decoded, navigator, realtime);
      }
    } catch (_) {
      _pendingPayload = payload;
    } finally {
      _isHandlingNavigation = false;
    }
  }

  bool _shouldSkipDuplicate(String key) {
    final DateTime now = DateTime.now();
    _recentNotifications.removeWhere(
      (_, DateTime shownAt) => now.difference(shownAt) > _dedupeWindow,
    );
    final DateTime? previous = _recentNotifications[key];
    if (previous != null && now.difference(previous) <= _dedupeWindow) {
      return true;
    }
    _recentNotifications[key] = now;
    return false;
  }

  Future<ByteArrayAndroidIcon?> _loadProfileIcon(int accountId) async {
    try {
      final Uri metadataUri = Uri.parse(
        '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/$accountId',
      );
      final http.Response metadataResponse = await http.get(metadataUri).timeout(
        kApiRequestTimeout,
      );
      if (metadataResponse.statusCode < 200 || metadataResponse.statusCode >= 300) {
        return null;
      }

      final dynamic decoded = jsonDecode(metadataResponse.body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final String? fileUrl = _resolvePublicUrl(
        (decoded['file_url'] ?? decoded['profile_photo']).toString(),
      );
      if (fileUrl == null) {
        return null;
      }

      final http.Response imageResponse = await http
          .get(Uri.parse(fileUrl))
          .timeout(kApiRequestTimeout);
      if (imageResponse.statusCode < 200 || imageResponse.statusCode >= 300) {
        return null;
      }
      final Uint8List bytes = imageResponse.bodyBytes;
      if (bytes.isEmpty) {
        return null;
      }
      return ByteArrayAndroidIcon.fromBase64String(base64Encode(bytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> _openMessagePayload(
    Map<String, dynamic> payload,
    NavigatorState navigator,
    UserRealtimeService realtime,
  ) async {
    final int? conversationId = _asInt(payload['conversation_id']);
    final String senderName = (payload['sender_name'] ?? 'Conversation')
        .toString()
        .trim();
    final int? senderAccountId = _asInt(payload['sender_account_id']);

    UserRealtimeConversation? conversation;
    if (conversationId != null && conversationId > 0) {
      conversation = _conversationForId(realtime, conversationId);
    }
    if (conversation == null && senderName.isNotEmpty) {
      conversation = _conversationForTitle(realtime, senderName);
    }

    if (conversation == null) {
      navigator.push(
        MaterialPageRoute(builder: (_) => const ChatsPage()),
      );
      return;
    }
    final UserRealtimeConversation resolvedConversation = conversation;

    realtime.openConversation(resolvedConversation.conversationId);
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatThreadPage(
          sellerName: resolvedConversation.title,
          lastMessage: resolvedConversation.lastMessageText ??
              resolvedConversation.conversationType,
          sellerAvatarUrl: _profilePictureUrl(
            resolvedConversation.otherAccountId ??
                senderAccountId ??
                resolvedConversation.conversationId,
          ),
          sellerAccountId: resolvedConversation.otherAccountId ?? senderAccountId,
          conversationId: resolvedConversation.conversationId,
          conversationType: resolvedConversation.conversationType,
          lastMessageAt: resolvedConversation.lastMessageAt,
          isStaffParticipant: _isStaffAccountType(
            resolvedConversation.otherAccountType,
          ),
        ),
      ),
    );
  }

  Future<void> _openNotificationPayload(
    Map<String, dynamic> payload,
    NavigatorState navigator,
    UserRealtimeService realtime,
  ) async {
    final int? notificationId = _asInt(payload['notification_id']);
    if (notificationId != null && notificationId > 0) {
      unawaited(realtime.markNotificationRead(notificationId));
    }

    final String type = (payload['notification_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final String entity = (payload['related_entity_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (entity == 'conversation' || entity == 'message' || entity == 'chat') {
      await _openMessagePayload(payload, navigator, realtime);
      return;
    }

    if (entity == 'listing' ||
        type.contains('listing') ||
        type.contains('inquiry') ||
        type.contains('transaction')) {
      final bool opened = await _openListingNotification(payload, navigator);
      if (opened) {
        return;
      }
    }

    if (type.contains('seller') ||
        type.contains('account') ||
        type.contains('warning') ||
        type.contains('verification') ||
        type.contains('welcome')) {
      navigator.push(
        MaterialPageRoute(builder: (_) => const UserProfilePage()),
      );
      return;
    }

    navigator.push(
      MaterialPageRoute(builder: (_) => const ChatsPage()),
    );
  }

  Future<bool> _openListingNotification(
    Map<String, dynamic> payload,
    NavigatorState navigator,
  ) async {
    final int? listingId = _asInt(payload['related_entity_id']);
    if (listingId == null || listingId <= 0) {
      return false;
    }

    try {
      final http.Response response = await http
          .get(
            ApiRoutes.listingById(listingId),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      final int resolvedListingId =
          _asInt(decoded['listing_id']) ??
          _asInt(decoded['id']) ??
          listingId;
      final int? ownerId =
          _asInt(decoded['owner_id']) ?? _asInt(decoded['seller_id']);
      final String sellerName =
          (decoded['seller_username'] ?? decoded['owner_username'] ?? 'Seller')
              .toString();
      final String imageUrl = _resolvePublicUrl(
            (decoded['primary_media_url'] ?? '').toString(),
          ) ??
          '';
      final String campus =
          (decoded['seller_campus'] ?? decoded['campus'] ?? '').toString();
      final String productTitle =
          (decoded['title'] ?? decoded['listing_title'] ?? 'Listing').toString();
      final String priceValue = (decoded['price'] ?? '').toString().trim();
      final String description =
          (decoded['description'] ?? '').toString().trim();
      final String? shareToken = (decoded['share_token'] ?? '')
              .toString()
              .trim()
              .isEmpty
          ? null
          : (decoded['share_token'] ?? '').toString().trim();
      final String? shareUrl = _resolvePublicUrl(
        (decoded['share_url'] ?? '').toString(),
      );

      navigator.push(
        MaterialPageRoute(
          builder: (_) => ProductDetailsPage(
            listingId: resolvedListingId,
            listingType: (decoded['listing_type'] ?? '').toString(),
            shareToken: shareToken,
            shareUrl: shareUrl,
            productName: productTitle,
            productPrice: priceValue.isEmpty ? 'Price unavailable' : 'PHP $priceValue',
            productLocation: campus,
            productDescription: description,
            imageUrls: imageUrl.isEmpty ? const <String>[] : <String>[imageUrl],
            sellerName: sellerName,
            sellerAccountId: ownerId,
            sellerAvatarUrl: ownerId == null ? '' : _profilePictureUrl(ownerId),
            sellerRating: 4.5,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  UserRealtimeConversation? _conversationForId(
    UserRealtimeService realtime,
    int conversationId,
  ) {
    for (final UserRealtimeConversation conversation in realtime.conversations) {
      if (conversation.conversationId == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  UserRealtimeConversation? _conversationForTitle(
    UserRealtimeService realtime,
    String title,
  ) {
    final String normalized = title.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    for (final UserRealtimeConversation conversation in realtime.conversations) {
      if (conversation.title.trim().toLowerCase() == normalized) {
        return conversation;
      }
    }
    return null;
  }

  bool _isStaffAccountType(String? accountType) {
    final String normalized = (accountType ?? '').trim().toLowerCase();
    return normalized == 'staff' ||
        normalized == 'management' ||
        normalized == 'superadmin';
  }

  String _profilePictureUrl(int accountId) {
    return '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/$accountId';
  }

  String? _resolvePublicUrl(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final Uri? parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }
    final Uri apiUri = Uri.parse(resolveApiBaseUrl());
    final Uri originUri = apiUri.replace(path: '/', query: null, fragment: null);
    return originUri.resolve(trimmed).toString();
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse((value ?? '').toString());
  }
}
