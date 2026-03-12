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

  static Uri transactions() {
    return _build(path: 'transactions/');
  }

  static Uri transactionsNoSlash() {
    return _build(path: 'transactions');
  }

  static Uri transactionById(int transactionId) {
    return _build(path: 'transactions/$transactionId');
  }

  static Uri cancelTransaction(int transactionId) {
    return _build(path: 'transactions/$transactionId/cancel');
  }

  static Uri transactionQr() {
    return _build(path: 'transaction-qr/');
  }

  static Uri transactionQrGenerate() {
    return _build(path: 'transaction-qr/generate');
  }

  static Uri transactionQrConfirm() {
    return _build(path: 'transaction-qr/confirm');
  }

  static Uri listings() {
    return _build(path: 'listings/');
  }

  static Uri listingById(int listingId) {
    return _build(path: 'listings/$listingId');
  }

  static Uri listingInquiries(int listingId, {int? accountId}) {
    return _build(
      path: 'listings/$listingId/inquiries',
      queryParameters: <String, dynamic>{
        if (accountId != null) 'account_id': '$accountId',
      },
    );
  }

  static Uri acceptListingInquiry(int listingId, int inquiryId) {
    return _build(path: 'listings/$listingId/inquiries/$inquiryId/accept');
  }

  static Uri rejectListingInquiry(int listingId, int inquiryId) {
    return _build(path: 'listings/$listingId/inquiries/$inquiryId/reject');
  }

  static Uri listingsForUser(int accountId) {
    return _build(path: 'listings/users/$accountId');
  }

  static Uri userInquiries(int accountId, {String? listingType}) {
    return _build(
      path: 'listings/users/$accountId/inquiries',
      queryParameters: <String, dynamic>{
        if (listingType != null && listingType.trim().isNotEmpty)
          'listing_type': listingType,
      },
    );
  }

  static Uri lookingForListingsForUser(int accountId) {
    return _build(path: 'listings/users/$accountId/looking-for');
  }

  static Uri listingMediaUpload() {
    return _build(path: 'listing-media/upload');
  }

  static Uri popularTags({int limit = 20}) {
    return _build(
      path: 'tags/popular',
      queryParameters: <String, dynamic>{
        'limit': '$limit',
      },
    );
  }

  static Uri listingsFeed({
    int? userId,
    List<String> tags = const <String>[],
    int limit = 20,
    int? offset,
  }) {
    final Map<String, dynamic> queryParameters = <String, dynamic>{
      'limit': '$limit',
      if (offset != null) 'offset': '$offset',
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
