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

  final String host = '192.168.1.12';
  return 'http://$host:$port/$apiPath';
}

String resolveWebSocketBaseUrl() {
  final Uri apiUri = Uri.parse(resolveApiBaseUrl());
  final String scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
  final List<String> trimmedSegments = List<String>.from(apiUri.pathSegments);
  if (trimmedSegments.length >= 2 &&
      trimmedSegments[trimmedSegments.length - 2] == 'api' &&
      trimmedSegments.last == 'v1') {
    trimmedSegments.removeLast();
    trimmedSegments.removeLast();
  }

  return apiUri.replace(
    scheme: scheme,
    pathSegments: trimmedSegments,
  ).toString();
}
