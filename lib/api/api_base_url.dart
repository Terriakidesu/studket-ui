import 'package:flutter/foundation.dart';

const Duration kApiRequestTimeout = Duration(seconds: 10);

String resolveApiBaseUrl({String apiPath = 'api/v1'}) {
  final String debugOverride = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  ).trim();

  if (kDebugMode && debugOverride.isNotEmpty) {
    return debugOverride;
  } 

  final String host = 'unliveable-lucille-threatless.ngrok-free.dev';
  return 'https://$host/$apiPath';
}

String? normalizeApiAssetUrl(String? raw) {
  final String trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final Uri apiUri = Uri.parse(resolveApiBaseUrl());
  final Uri originUri = apiUri.replace(
    path: '/',
    query: null,
    fragment: null,
  );
  final Uri? parsed = Uri.tryParse(trimmed);

  if (parsed != null && parsed.hasScheme) {
    if (_isLocalAssetHost(parsed.host)) {
      return parsed.replace(
        scheme: originUri.scheme,
        host: originUri.host,
        port: originUri.hasPort ? originUri.port : 0,
      ).toString();
    }
    return parsed.toString();
  }

  if (trimmed.startsWith('//')) {
    return '${originUri.scheme}:$trimmed';
  }

  return originUri.resolve(trimmed).toString();
}

bool _isLocalAssetHost(String host) {
  final String normalized = host.trim().toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '10.0.2.2';
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
