import 'package:flutter/material.dart';

import 'app.dart';
import 'app_notifications.dart';
import 'app_theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppNotifications.instance.initialize();
  await AppThemeController.instance.restore();
  runApp(const MyApp());
}
