import 'dart:io';

import 'package:flutter/foundation.dart';

const Duration kApiRequestTimeout = Duration(seconds: 10);

String resolveApiBaseUrl({String apiPath = 'api/v1'}) {

  final int port = 8088;

  final String debugOverride = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  ).trim();

  if (kDebugMode && debugOverride.isNotEmpty) {
    return debugOverride;
  }

  final String host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
  return 'http://$host:$port/$apiPath';
}
