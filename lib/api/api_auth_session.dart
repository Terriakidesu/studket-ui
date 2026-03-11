class ApiAuthSession {
  ApiAuthSession._();

  static String? _bearerToken;
  static String? _cookie;
  static int? _accountId;
  static String? _email;
  static String? _username;
  static String? _accountType;
  static String? _marketplaceRole;
  static bool _trustedSeller = false;

  static void setBearerToken(String? token) {
    final String normalized = (token ?? '').trim();
    _bearerToken = normalized.isEmpty ? null : normalized;
  }

  static void setCookieFromSetCookieHeader(String? setCookieHeader) {
    final String header = (setCookieHeader ?? '').trim();
    if (header.isEmpty) return;

    final String cookieValue = header.split(';').first.trim();
    if (cookieValue.isNotEmpty) {
      _cookie = cookieValue;
    }
  }

  static Map<String, String> authHeaders() {
    final Map<String, String> headers = <String, String>{};

    if (_bearerToken != null) {
      headers['Authorization'] = 'Bearer $_bearerToken';
    }
    if (_cookie != null) {
      headers['Cookie'] = _cookie!;
    }

    return headers;
  }

  static int? get accountId => _accountId;
  static String? get email => _email;
  static String? get username => _username;
  static String? get accountType => _accountType;
  static String? get marketplaceRole => _marketplaceRole;
  static bool get trustedSeller => _trustedSeller;

  static bool get isSeller => _marketplaceRole == 'seller';

  static void setAccount({
    required int? accountId,
    required String? email,
    required String? username,
    required String? accountType,
    required String? marketplaceRole,
    required bool trustedSeller,
  }) {
    _accountId = accountId;
    _email = _normalize(email);
    _username = _normalize(username);
    _accountType = _normalize(accountType);
    _marketplaceRole = _normalize(marketplaceRole);
    _trustedSeller = trustedSeller;
  }

  static void clear() {
    _bearerToken = null;
    _cookie = null;
    _accountId = null;
    _email = null;
    _username = null;
    _accountType = null;
    _marketplaceRole = null;
    _trustedSeller = false;
  }

  static String? _normalize(String? value) {
    final String normalized = (value ?? '').trim();
    return normalized.isEmpty ? null : normalized;
  }
}
