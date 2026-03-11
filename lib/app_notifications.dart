import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
  }) async {
    if (!_isInitialized) {
      return;
    }

    if (_shouldSkipDuplicate('message:$messageId')) {
      return;
    }

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
}
