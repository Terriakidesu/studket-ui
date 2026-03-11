import '../api/api_base_url.dart';

class FeedListing {
  const FeedListing({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.description,
    required this.imageUrls,
    required this.price,
    required this.campus,
    required this.tags,
    required this.listingType,
    required this.status,
    required this.sellerUsername,
    required this.sellerAvatarUrl,
    required this.sellerAverageRating,
    required this.sellerReviewCount,
    required this.sellerIsTrusted,
  });

  final int id;
  final int? ownerId;
  final String title;
  final String description;
  final List<String> imageUrls;
  final num? price;
  final String campus;
  final List<String> tags;
  final String listingType;
  final String status;
  final String sellerUsername;
  final String? sellerAvatarUrl;
  final num? sellerAverageRating;
  final int sellerReviewCount;
  final bool sellerIsTrusted;

  factory FeedListing.fromJson(Map<String, dynamic> json) {
    return FeedListing(
      id: (json['listing_id'] as num?)?.toInt() ?? 0,
      ownerId: (json['owner_id'] as num?)?.toInt() ??
          (json['seller_id'] as num?)?.toInt() ??
          (json['account_id'] as num?)?.toInt(),
      title: (json['title'] ?? 'Untitled Listing').toString(),
      description: (json['description'] ?? '').toString(),
      imageUrls: _extractImageUrls(json),
      price: json['price'] as num?,
      campus: (json['seller_campus'] ?? 'Campus not provided').toString(),
      tags: (json['tags'] is List)
          ? (json['tags'] as List<dynamic>)
                .map((dynamic value) => value.toString())
                .toList(growable: false)
          : const <String>[],
      listingType: (json['listing_type'] ?? 'listing').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      sellerUsername: (json['seller_username'] ?? 'Unknown seller').toString(),
      sellerAvatarUrl: _extractSellerAvatarUrl(json),
      sellerAverageRating: json['seller_average_rating'] as num?,
      sellerReviewCount: (json['seller_review_count'] as num?)?.toInt() ?? 0,
      sellerIsTrusted:
          json['seller_is_trusted'] == true || json['seller_is_verified'] == true,
    );
  }

  static List<String> _extractImageUrls(Map<String, dynamic> json) {
    final List<dynamic> rawCollections = <dynamic>[
      json['image_urls'],
      json['images'],
      json['media_urls'],
      json['media'],
      json['listing_media'],
      json['photos'],
    ];

    final List<String> urls = <String>[];
    for (final dynamic collection in rawCollections) {
      if (collection is! List) {
        continue;
      }
      for (final dynamic item in collection) {
        final String? url = _extractSingleImageUrl(item);
        if (url != null && !urls.contains(url)) {
          urls.add(url);
        }
      }
    }
    return List<String>.unmodifiable(urls);
  }

  static String? _extractSingleImageUrl(dynamic value) {
    if (value is String) {
      return _normalizeImageUrl(value);
    }
    if (value is! Map) {
      return null;
    }

    for (final String key in <String>[
      'image_url',
      'url',
      'media_url',
      'file_url',
      'src',
      'secure_url',
    ]) {
      final String? normalized = _normalizeImageUrl(value[key]?.toString());
      if (normalized != null) {
        return normalized;
      }
    }

    return null;
  }

  static String? _extractSellerAvatarUrl(Map<String, dynamic> json) {
    final List<dynamic> candidates = <dynamic>[
      json['seller_avatar_url'],
      json['seller_profile_photo'],
      json['seller_image_url'],
      json['profile_photo'],
      json['avatar_url'],
      if (json['seller'] is Map<String, dynamic>) ...<dynamic>[
        (json['seller'] as Map<String, dynamic>)['avatar_url'],
        (json['seller'] as Map<String, dynamic>)['profile_photo'],
        (json['seller'] as Map<String, dynamic>)['image_url'],
      ],
    ];

    for (final dynamic candidate in candidates) {
      final String? normalized = _normalizeImageUrl(candidate?.toString());
      if (normalized != null) {
        return normalized;
      }
    }
    return null;
  }

  static String? _normalizeImageUrl(String? raw) {
    return normalizeApiAssetUrl(raw);
  }
}
