import 'api_base_url.dart';

class ApiRoutes {
  const ApiRoutes._();

  static Uri authLogin() {
    return _build(path: 'auth/login');
  }

  static Uri authRegister() {
    return _build(path: 'auth/register');
  }

  static Uri requestSellerAccess() {
    return _build(path: 'auth/seller-status/request');
  }

  static Uri elevateSellerAccess() {
    return _build(path: 'auth/seller-status/elevate');
  }

  static Uri conversations() {
    return _build(path: 'conversations/');
  }

  static Uri messages() {
    return _build(path: 'messages/');
  }

  static Uri listings() {
    return _build(path: 'listings/');
  }

  static Uri listingMediaUpload() {
    return _build(path: 'listing-media/upload');
  }

  static Uri listingsFeed({
    int? userId,
    List<String> tags = const <String>[],
    int limit = 20,
  }) {
    final Map<String, dynamic> queryParameters = <String, dynamic>{
      'limit': '$limit',
      if (userId != null) 'user_id': '$userId',
      if (tags.isNotEmpty) 'tags': tags,
    };
    return _build(path: 'listings/feed', queryParameters: queryParameters);
  }

  static Uri _build({
    required String path,
    Map<String, dynamic>? queryParameters,
  }) {
    final String baseUrl = resolveApiBaseUrl();
    final String normalizedPath = path.startsWith('/') ? path : '/$path';
    final Uri uri = Uri.parse('$baseUrl$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return uri;
    }

    final Map<String, dynamic> normalized = <String, dynamic>{};
    queryParameters.forEach((String key, dynamic value) {
      if (value != null) {
        normalized[key] = value;
      }
    });
    return uri.replace(queryParameters: normalized);
  }
}
