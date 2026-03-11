import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_auth_session.dart';
import 'api_base_url.dart';
import 'api_routes.dart';

class AuthApi {
  const AuthApi._();

  static Future<void> login({
    required String emailOrUsername,
    required String password,
  }) async {
    final http.Response response = await _postJsonFollowRedirect(
      ApiRoutes.authLogin(),
      <String, dynamic>{
        'email_or_username': emailOrUsername.trim(),
        'password': password,
        'account_type': 'user',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response, isLogin: true));
    }

    _storeSessionFromAuthResponse(response);
  }

  static Future<void> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList(growable: false);
    final String firstName = parts.isEmpty ? '' : parts.first;
    final String lastName = parts.length <= 1 ? '' : parts.skip(1).join(' ');

    final http.Response response = await _postJsonFollowRedirect(
      ApiRoutes.authRegister(),
      <String, dynamic>{
        'email': email.trim(),
        'username': _buildUsername(name: name, email: email),
        'password': password,
        'account_type': 'user',
        'first_name': firstName.isEmpty ? null : firstName,
        'last_name': lastName.isEmpty ? null : lastName,
        'campus': null,
        'role_name': null,
        'superadmin_code': null,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response, isLogin: false));
    }

    _storeSessionFromAuthResponse(response);
  }

  static Future<void> requestSellerStatus({String? submissionNote}) async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      throw const HttpException('No authenticated account id found.');
    }

    final http.Response response = await _postJsonFollowRedirect(
      ApiRoutes.requestSellerAccess(),
      <String, dynamic>{
        'account_id': accountId,
        if ((submissionNote ?? '').trim().isNotEmpty)
          'submission_note': submissionNote!.trim(),
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response, isLogin: false));
    }
  }

  static String _extractErrorMessage(
    http.Response response, {
    required bool isLogin,
  }) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      final String? message = _extractMessage(decoded);
      if (message != null && message.isNotEmpty) {
        if (isLogin && response.statusCode == 401) {
          return message == 'Invalid credentials'
              ? 'Invalid email/username or password.'
              : message;
        }
        return message;
      }
    } catch (_) {}
    return 'Request failed (HTTP ${response.statusCode}).';
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static void _storeSessionFromAuthResponse(http.Response response) {
    ApiAuthSession.setCookieFromSetCookieHeader(response.headers['set-cookie']);

    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return;
      }

      final dynamic token =
          decoded['access_token'] ??
          decoded['access'] ??
          decoded['token'] ??
          decoded['auth_token'] ??
          decoded['key'];
      if (token is String && token.trim().isNotEmpty) {
        ApiAuthSession.setBearerToken(token);
      }

      final Map<String, dynamic>? account =
          decoded['account'] is Map<String, dynamic>
          ? decoded['account'] as Map<String, dynamic>
          : null;

      final dynamic accountId = account?['account_id'] ?? decoded['account_id'];
      final dynamic email = account?['email'] ?? decoded['email'];
      final dynamic username = account?['username'] ?? decoded['username'];
      final dynamic accountType =
          account?['account_type'] ?? decoded['account_type'];
      final dynamic marketplaceRole =
          account?['marketplace_role'] ?? decoded['marketplace_role'];

      ApiAuthSession.setAccount(
        accountId: accountId is int ? accountId : int.tryParse('$accountId'),
        email: email?.toString(),
        username: username?.toString(),
        accountType: accountType?.toString(),
        marketplaceRole: marketplaceRole?.toString(),
      );
    } catch (_) {}
  }

  static Future<http.Response> _postJsonFollowRedirect(
    Uri uri,
    Map<String, dynamic> body,
  ) async {
    const Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    http.Response response = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(kApiRequestTimeout);

    if (_isRedirectStatus(response.statusCode)) {
      final String? location = response.headers['location'];
      if (location != null && location.isNotEmpty) {
        final Uri redirectedUri = uri.resolve(location);
        response = await http
            .post(redirectedUri, headers: headers, body: jsonEncode(body))
            .timeout(kApiRequestTimeout);
      }
    }

    return response;
  }

  static String _buildUsername({
    required String name,
    required String email,
  }) {
    final String fromName = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (fromName.isNotEmpty) {
      return fromName;
    }

    final String localPart = email.split('@').first.trim().toLowerCase();
    return localPart.isEmpty ? 'studket_user' : localPart;
  }

  static String? _extractMessage(dynamic decoded) {
    if (decoded is String) {
      return decoded.trim();
    }

    if (decoded is Map<String, dynamic>) {
      for (final dynamic value in <dynamic>[
        decoded['message'],
        decoded['error'],
        decoded['detail'],
      ]) {
        final String? nested = _extractMessage(value);
        if (nested != null && nested.isNotEmpty) {
          return nested;
        }
      }
    }

    if (decoded is List && decoded.isNotEmpty) {
      return _extractMessage(decoded.first);
    }

    return null;
  }
}
