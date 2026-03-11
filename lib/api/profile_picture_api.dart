import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_auth_session.dart';
import 'api_base_url.dart';

class ProfilePictureApi {
  ProfilePictureApi._();

  static final Map<int, Future<String?>> _cache = <int, Future<String?>>{};

  static Future<String?> resolveForAccount(int? accountId) {
    final int? normalizedId = accountId;
    if (normalizedId == null || normalizedId <= 0) {
      return Future<String?>.value(null);
    }
    return _cache.putIfAbsent(
      normalizedId,
      () => _fetchProfilePictureUrl(normalizedId),
    );
  }

  static void clearCache() {
    _cache.clear();
  }

  static Future<String?> generateForAccount(int? accountId) async {
    final int? normalizedId = accountId;
    if (normalizedId == null || normalizedId <= 0) {
      throw const HttpException('No valid account id found.');
    }

    final Uri endpoint = Uri.parse(
      '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/generate',
    );
    final http.Response response = await http
        .post(
          endpoint,
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(<String, dynamic>{'account_id': normalizedId}),
        )
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }

    _cache.remove(normalizedId);
    return resolveForAccount(normalizedId);
  }

  static Future<String?> uploadForAccount({
    required int? accountId,
    required File file,
  }) async {
    final int? normalizedId = accountId;
    if (normalizedId == null || normalizedId <= 0) {
      throw const HttpException('No valid account id found.');
    }

    final Uri endpoint = Uri.parse(
      '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/upload',
    );
    final http.MultipartRequest request = http.MultipartRequest(
      'POST',
      endpoint,
    );
    request.headers.addAll(ApiAuthSession.authHeaders());
    request.fields['account_id'] = '$normalizedId';
    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    final http.StreamedResponse streamed = await request.send().timeout(
      kApiRequestTimeout,
    );
    final http.Response response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }

    _cache.remove(normalizedId);
    return resolveForAccount(normalizedId);
  }

  static Future<String?> _fetchProfilePictureUrl(int accountId) async {
    final Uri endpoint = Uri.parse(
      '${resolveApiBaseUrl(apiPath: 'api/v1')}/profile-pictures/$accountId',
    );
    final http.Response response = await http
        .get(
          endpoint,
          headers: <String, String>{
            'Accept': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
        )
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final dynamic rawUrl =
        decoded['file_url'] ??
        decoded['profile_photo'] ??
        decoded['url'] ??
        decoded['image_url'];
    final String value = (rawUrl ?? '').toString().trim();
    if (value.isEmpty) {
      return null;
    }

    return endpoint.resolve(value).toString();
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        final dynamic message =
            decoded['message'] ?? decoded['error'] ?? decoded['detail'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return 'Profile picture request failed (HTTP ${response.statusCode}).';
  }
}
