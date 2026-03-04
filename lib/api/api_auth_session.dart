class ApiAuthSession {
  ApiAuthSession._();

  static String? _bearerToken;
  static String? _cookie;

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
}
