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
    required String email,
    required String password,
  }) async {
    final http.Response response = await _postJsonFollowRedirect(
      ApiRoutes.authLogin(),
      <String, String>{'email': email.trim(), 'password': password},
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
    required String confirmPassword,
  }) async {
    final http.Response response = await _postJsonFollowRedirect(
      ApiRoutes.authRegister(),
      <String, String>{
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        'confirm_password': confirmPassword,
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response, isLogin: false));
    }

    _storeSessionFromAuthResponse(response);
  }

  static String _extractErrorMessage(
    http.Response response, {
    required bool isLogin,
  }) {
    if (isLogin && response.statusCode == 401) {
      return 'Invalid email or password.';
    }

    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic message = decoded['message'] ?? decoded['detail'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
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
      if (decoded is! Map<String, dynamic>) return;

      final dynamic token =
          decoded['access_token'] ??
          decoded['access'] ??
          decoded['token'] ??
          decoded['auth_token'] ??
          decoded['key'];
      if (token is String && token.trim().isNotEmpty) {
        ApiAuthSession.setBearerToken(token);
      }
    } catch (_) {}
  }

  static Future<http.Response> _postJsonFollowRedirect(
    Uri uri,
    Map<String, String> body,
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
}
