import 'package:shared_preferences/shared_preferences.dart';

import 'api_auth_session.dart';

class ApiSessionStorage {
  ApiSessionStorage._();

  static const String _bearerTokenKey = 'api_session_bearer_token';
  static const String _cookieKey = 'api_session_cookie';
  static const String _accountIdKey = 'api_session_account_id';
  static const String _emailKey = 'api_session_email';
  static const String _usernameKey = 'api_session_username';
  static const String _accountTypeKey = 'api_session_account_type';
  static const String _marketplaceRoleKey = 'api_session_marketplace_role';
  static const String _trustedSellerKey = 'api_session_trusted_seller';

  static Future<void> saveCurrentSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setString(_bearerTokenKey, ApiAuthSession.bearerToken ?? '');
    await prefs.setString(_cookieKey, ApiAuthSession.cookie ?? '');

    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      await prefs.remove(_accountIdKey);
    } else {
      await prefs.setInt(_accountIdKey, accountId);
    }

    await prefs.setString(_emailKey, ApiAuthSession.email ?? '');
    await prefs.setString(_usernameKey, ApiAuthSession.username ?? '');
    await prefs.setString(_accountTypeKey, ApiAuthSession.accountType ?? '');
    await prefs.setString(
      _marketplaceRoleKey,
      ApiAuthSession.marketplaceRole ?? '',
    );
    await prefs.setBool(_trustedSellerKey, ApiAuthSession.trustedSeller);
  }

  static Future<bool> restoreSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? accountId = prefs.getInt(_accountIdKey);
    final String? email = _readString(prefs, _emailKey);
    final String? username = _readString(prefs, _usernameKey);

    if (accountId == null && email == null && username == null) {
      return false;
    }

    ApiAuthSession.restore(
      bearerToken: _readString(prefs, _bearerTokenKey),
      cookie: _readString(prefs, _cookieKey),
      accountId: accountId,
      email: email,
      username: username,
      accountType: _readString(prefs, _accountTypeKey),
      marketplaceRole: _readString(prefs, _marketplaceRoleKey),
      trustedSeller: prefs.getBool(_trustedSellerKey) ?? false,
    );
    return true;
  }

  static Future<void> clear() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_bearerTokenKey);
    await prefs.remove(_cookieKey);
    await prefs.remove(_accountIdKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_accountTypeKey);
    await prefs.remove(_marketplaceRoleKey);
    await prefs.remove(_trustedSellerKey);
  }

  static String? _readString(SharedPreferences prefs, String key) {
    final String value = (prefs.getString(key) ?? '').trim();
    return value.isEmpty ? null : value;
  }
}
