import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_auth_session.dart';
import 'api_base_url.dart';
import 'api_routes.dart';

class TagsApi {
  const TagsApi._();

  static Future<List<String>> fetchPopularTags({int limit = 20}) async {
    final Uri uri = ApiRoutes.popularTags(limit: limit);
    if (kDebugMode) {
      debugPrint('TagsApi.fetchPopularTags -> GET $uri');
    }
    final http.Response response = await http
        .get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            ...ApiAuthSession.authHeaders(),
          },
        )
        .timeout(kApiRequestTimeout);

    if (kDebugMode) {
      debugPrint(
        'TagsApi.fetchPopularTags <- HTTP ${response.statusCode} $uri',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Popular tags request failed (HTTP ${response.statusCode}).');
    }

    final dynamic decoded = jsonDecode(response.body);
    final int? reportedCount = decoded is Map<String, dynamic>
        ? (decoded['count'] as num?)?.toInt()
        : null;
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? (decoded['items'] as List<dynamic>? ??
              decoded['tags'] as List<dynamic>? ??
              decoded['results'] as List<dynamic>? ??
              const <dynamic>[])
        : const <dynamic>[];

    final List<String> normalized = items
        .map((dynamic item) {
          if (item is String) {
            return item.trim();
          }
          if (item is Map<String, dynamic>) {
            final dynamic value =
                item['tag_name'] ??
                item['tag'] ??
                item['name'] ??
                item['label'];
            return value?.toString().trim() ?? '';
          }
          return item.toString().trim();
        })
        .where((String value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (kDebugMode) {
      debugPrint(
        'TagsApi.fetchPopularTags parsed ${normalized.length} tags '
        '(reported count: ${reportedCount ?? 'n/a'}): $normalized',
      );
    }

    final int availableCount = reportedCount ?? normalized.length;
    if (availableCount < 10 || normalized.length < 10) {
      if (kDebugMode) {
        debugPrint(
          'TagsApi.fetchPopularTags fallback -> not enough tags '
          '(need at least 10, got count=$availableCount parsed=${normalized.length})',
        );
      }
      return const <String>[];
    }

    return normalized;
  }
}
