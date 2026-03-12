import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_auth_session.dart';
import 'api_base_url.dart';
import 'api_routes.dart';

class ListingsApi {
  const ListingsApi._();

  static Map<String, dynamic> _buildListingPayload({
    int? ownerId,
    String? title,
    String? description,
    String? listingType,
    num? price,
    num? budgetMin,
    num? budgetMax,
    String? condition,
    List<String> tags = const <String>[],
    String? status,
  }) {
    final String? normalizedCondition = condition?.trim();
    final Map<String, dynamic> payload = <String, dynamic>{};
    if (ownerId != null) {
      payload['owner_id'] = ownerId;
    }
    if (title != null) {
      payload['title'] = title.trim();
    }
    if (description != null) {
      payload['description'] = description.trim();
    }
    if (listingType != null) {
      payload['listing_type'] = listingType;
    }
    if (status != null) {
      payload['status'] = status;
    }
    if (price != null) {
      payload['price'] = price;
    }
    if (budgetMin != null) {
      payload['budget_min'] = budgetMin;
    }
    if (budgetMax != null) {
      payload['budget_max'] = budgetMax;
    }
    if ((normalizedCondition ?? '').isNotEmpty) {
      payload['condition'] = normalizedCondition;
    }
    if (tags.isNotEmpty) {
      payload['tags'] = tags;
    }
    return payload;
  }

  static Future<Map<String, dynamic>> createListing({
    required String title,
    required String description,
    required String listingType,
    num? price,
    num? budgetMin,
    num? budgetMax,
    String? condition,
    List<String> tags = const <String>[],
  }) async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      throw const HttpException('No authenticated account id found.');
    }

    final Map<String, dynamic> payload = _buildListingPayload(
      ownerId: accountId,
      title: title,
      description: description,
      listingType: listingType,
      status: 'available',
      price: price,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      condition: condition,
      tags: tags,
    );

    final http.Response response = await http
        .post(
          ApiRoutes.listings(),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(payload),
        )
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> updateListing({
    required int listingId,
    required String title,
    required String description,
    required String listingType,
    num? price,
    num? budgetMin,
    num? budgetMax,
    String? condition,
    List<String> tags = const <String>[],
    String status = 'available',
  }) async {
    final Map<String, dynamic> payload = _buildListingPayload(
      title: title,
      description: description,
      listingType: listingType,
      status: status,
      price: price,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      condition: condition,
      tags: tags,
    );

    final http.Response response = await http
        .patch(
          ApiRoutes.listingById(listingId),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
          body: jsonEncode(payload),
        )
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{};
  }

  static Future<void> deleteListing({required int listingId}) async {
    final http.Response response = await http
        .delete(
          ApiRoutes.listingById(listingId),
          headers: <String, String>{
            'Accept': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
        )
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }
  }

  static Future<void> uploadListingMedia({
    required int listingId,
    required List<File> files,
  }) async {
    if (files.isEmpty) {
      return;
    }

    final http.MultipartRequest request = http.MultipartRequest(
      'POST',
      ApiRoutes.listingMediaUpload(),
    );
    request.headers.addAll(ApiAuthSession.authHeaders());
    request.fields['listing_id'] = '$listingId';
    request.fields['sort_order'] = '0';

    for (final File file in files) {
      request.files.add(await http.MultipartFile.fromPath('files', file.path));
    }

    final http.StreamedResponse streamed = await request.send().timeout(
      kApiUploadTimeout,
    );
    final http.Response response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(_extractErrorMessage(response));
    }
  }

  static int? extractListingId(Map<String, dynamic> json) {
    final dynamic value = json['listing_id'] ?? json['id'] ?? json['item_id'];
    if (value is int) {
      return value;
    }
    return int.tryParse('$value');
  }

  static String _extractErrorMessage(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      final String? message = _extractMessage(decoded);
      if (message != null && message.isNotEmpty) {
        return message;
      }
    } catch (_) {}
    return 'Request failed (HTTP ${response.statusCode}).';
  }

  static String? _extractMessage(dynamic decoded) {
    if (decoded is String && decoded.trim().isNotEmpty) {
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
