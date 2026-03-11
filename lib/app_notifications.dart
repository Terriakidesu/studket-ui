import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'api/api_base_url.dart';

class AppNotifications {
  AppNotifications._();

  static final AppNotifications instance = AppNotifications._();

  static const String _messagesChannelId = 'studket_messages';
  static const String _notificationsChannelId = 'studket_notifications';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<String, DateTime> _recentNotifications = <String, DateTime>{};

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
    );

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
      messageText,
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
                messageText,
                DateTime.now(),
                senderPerson,
              ),
            ],
          ),
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      ),
    );
  }

  Future<void> showRealtimeNotification({
    required int notificationId,
    required String title,
    required String body,
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
    );
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
      final Uri uri = Uri.parse(
        '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/$accountId',
      );
      final http.Response response = await http.get(uri).timeout(
        kApiRequestTimeout,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final Uint8List bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        return null;
      }
      return ByteArrayAndroidIcon.fromBase64String(base64Encode(bytes));
    } catch (_) {
      return null;
    }
  }
}
