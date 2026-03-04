import 'api_base_url.dart';

class ApiRoutes {
  const ApiRoutes._();

  static Uri products() {
    return _build(path: 'products/');
  }

  static Uri authLogin() {
    return _build(path: 'auth/login');
  }

  static Uri authRegister() {
    return _build(path: 'auth/register');
  }

  static Uri _build({required String path}) {
    final String baseUrl = resolveApiBaseUrl();
    final String normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath');
  }
}
