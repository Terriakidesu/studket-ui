import 'api_base_url.dart';

class ApiRoutes {
  const ApiRoutes._();

  static Uri products({required int port}) {
    return _build(port: port, path: 'products/');
  }

  static Uri _build({required int port, required String path}) {
    final String baseUrl = resolveApiBaseUrl(port: port);
    final String normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }
}
