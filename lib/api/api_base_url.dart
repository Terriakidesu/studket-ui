import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Duration kApiRequestTimeout = Duration(seconds: 10);
const Duration kApiUploadTimeout = Duration(seconds: 60);
const String _debugApiBaseUrlOverrideKey = 'debug_api_base_url_override';

String? _debugApiBaseUrlOverride;

Future<void> restoreDebugApiBaseUrlOverride() async {
  if (!kDebugMode) {
    _debugApiBaseUrlOverride = null;
    return;
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  _debugApiBaseUrlOverride = _readNormalizedDebugApiBaseUrlOverride(prefs);
}

String? getDebugApiBaseUrlOverride() => _debugApiBaseUrlOverride;

Future<void> setDebugApiBaseUrlOverride(String? rawValue) async {
  if (!kDebugMode) {
    return;
  }

  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? normalized = _normalizeDebugApiBaseUrlOverride(rawValue);

  if (normalized == null) {
    _debugApiBaseUrlOverride = null;
    await prefs.remove(_debugApiBaseUrlOverrideKey);
    return;
  }

  _debugApiBaseUrlOverride = normalized;
  await prefs.setString(_debugApiBaseUrlOverrideKey, normalized);
}

String resolveApiBaseUrl({String apiPath = 'api/v1'}) {
  if (kDebugMode && _debugApiBaseUrlOverride != null) {
    return _debugApiBaseUrlOverride!;
  }

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

String? _readNormalizedDebugApiBaseUrlOverride(SharedPreferences prefs) {
  final String rawValue = (prefs.getString(_debugApiBaseUrlOverrideKey) ?? '')
      .trim();
  if (rawValue.isEmpty) {
    return null;
  }

  try {
    return _normalizeDebugApiBaseUrlOverride(rawValue);
  } on FormatException {
    prefs.remove(_debugApiBaseUrlOverrideKey);
    return null;
  }
}

String? _normalizeDebugApiBaseUrlOverride(String? rawValue) {
  final String trimmed = (rawValue ?? '').trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final Uri? parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme || parsed.host.trim().isEmpty) {
    throw const FormatException('Enter a full http:// or https:// URL.');
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    throw const FormatException('Only http:// and https:// URLs are supported.');
  }

  final List<String> pathSegments = parsed.pathSegments
      .where((String segment) => segment.isNotEmpty)
      .toList(growable: false);
  final List<String> normalizedPathSegments = pathSegments.isEmpty
      ? const <String>['api', 'v1']
      : pathSegments;

  return parsed.replace(
    pathSegments: normalizedPathSegments,
    query: null,
    fragment: null,
  ).toString();
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
