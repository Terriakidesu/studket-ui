import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'chats_page.dart';
import 'seller_profile_page.dart';
import 'network_cached_image.dart';
import 'components/account_avatar.dart';
import 'components/rating_stars.dart';
import 'components/studket_app_bar.dart';
import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';

class ProductDetailsPage extends StatefulWidget {
  const ProductDetailsPage({
    super.key,
    required this.listingId,
    this.listingType,
    this.shareToken,
    this.shareUrl,
    required this.productName,
    required this.productPrice,
    required this.productLocation,
    required this.productDescription,
    required this.imageUrls,
    required this.sellerName,
    required this.sellerAccountId,
    required this.sellerAvatarUrl,
    required this.sellerRating,
  });

  final int listingId;
  final String? listingType;
  final String? shareToken;
  final String? shareUrl;
  final String productName;
  final String productPrice;
  final String productLocation;
  final String productDescription;
  final List<String> imageUrls;
  final String sellerName;
  final int? sellerAccountId;
  final String sellerAvatarUrl;
  final double sellerRating;

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  int _currentImageIndex = 0;
  double? _derivedSellerRating;
  int _sellerReviewCount = 0;
  bool _isLoadingSellerRating = false;

  bool get _hasImages => widget.imageUrls.isNotEmpty;
  bool get _isLookingFor =>
      (widget.listingType ?? '').trim().toLowerCase() == 'looking_for';

  String? get _resolvedShareUrl {
    final String directUrl = (widget.shareUrl ?? '').trim();
    if (directUrl.isNotEmpty) {
      return directUrl;
    }
    final String token = (widget.shareToken ?? '').trim();
    if (token.isEmpty) {
      return null;
    }
    final Uri apiUri = Uri.parse(resolveApiBaseUrl());
    final Uri originUri = apiUri.replace(
      path: '/',
      query: null,
      fragment: null,
    );
    return originUri.resolve('/share/$token').toString();
  }

  @override
  void initState() {
    super.initState();
    if (widget.sellerAccountId != null) {
      _loadSellerRating();
    }
  }

  double get _displaySellerRating =>
      _derivedSellerRating ?? widget.sellerRating;

  Future<void> _loadSellerRating() async {
    final int? sellerId = widget.sellerAccountId;
    if (sellerId == null || _isLoadingSellerRating) {
      return;
    }

    setState(() {
      _isLoadingSellerRating = true;
    });

    try {
      final http.Response response = await http
          .get(
            ApiRoutes.reviewsForUser(sellerId),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final List<int> ratings = _extractRatings(response.body);
      if (!mounted) {
        return;
      }
      if (ratings.isEmpty) {
        setState(() {
          _sellerReviewCount = 0;
        });
        return;
      }
      final int total = ratings.fold<int>(0, (sum, value) => sum + value);
      setState(() {
        _sellerReviewCount = ratings.length;
        _derivedSellerRating = total / ratings.length;
      });
    } catch (_) {
      // Ignore seller rating load failures.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSellerRating = false;
        });
      }
    }
  }

  List<int> _extractRatings(String body) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
            ? (decoded['items'] as List<dynamic>? ?? const <dynamic>[])
            : const <dynamic>[];

    return items
        .whereType<Map<String, dynamic>>()
        .map((item) => (item['rating'] as num?)?.toInt() ?? 0)
        .where((value) => value > 0)
        .toList(growable: false);
  }

  Future<void> _copyShareUrl() async {
    final String? shareUrl = _resolvedShareUrl;
    if (shareUrl == null || shareUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This listing does not have a share link yet.')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Share link copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StudketAppBar(
        title: 'Listing',
        actions: [
          IconButton(
            tooltip: 'Copy share link',
            onPressed: _copyShareUrl,
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          MediaQuery.of(context).viewPadding.bottom + 16,
        ),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.35),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () {
              if (widget.sellerAccountId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This listing is missing the seller details needed for chat.',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatThreadPage(
                    sellerName: widget.sellerName,
                    lastMessage: _isLookingFor
                        ? 'Hi, I saw your looking for post.'
                        : 'Hi, is this still available?',
                    initialMessageText: _isLookingFor
                        ? 'Hi, I saw your looking for post about ${widget.productName}. Can you share more details about what you need?'
                        : 'Hi, is this still available for ${widget.productName}?',
                    sellerAccountId: widget.sellerAccountId,
                    sellerAvatarUrl: widget.sellerAvatarUrl,
                    inquiryProducts: <InquiryProductData>[
                      InquiryProductData(
                        listingId: widget.listingId,
                        name: widget.productName,
                        description: widget.productDescription,
                        price: widget.productPrice,
                        location: widget.productLocation,
                        listingType: widget.listingType ?? 'listing',
                        imageUrl: _hasImages ? widget.imageUrls.first : '',
                      ),
                    ],
                  ),
                ),
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_rounded, size: 20),
                SizedBox(width: 8),
                Text('Inquire Now'),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_isLookingFor) ...[
              AspectRatio(
                aspectRatio: 1,
                child: _hasImages
                    ? PageView.builder(
                        itemCount: widget.imageUrls.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentImageIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          return NetworkCachedImage(
                            imageUrl: widget.imageUrls[index],
                            fit: BoxFit.cover,
                            width: double.infinity,
                          );
                        },
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHigh,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.image_outlined,
                          size: 56,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              if (_hasImages)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.imageUrls.length, (index) {
                    final bool isActive = index == _currentImageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[300],
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.productName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.productPrice,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.productLocation,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Description',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.productDescription,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Seller',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    elevation: 0.5,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                          builder: (_) => SellerProfilePage(
                            sellerName: widget.sellerName,
                            sellerAvatarUrl: widget.sellerAvatarUrl,
                            sellerRating: widget.sellerRating,
                            sellerAccountId: widget.sellerAccountId,
                          ),
                        ),
                      );
                    },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            AccountAvatar(
                              accountId: widget.sellerAccountId,
                              radius: 24,
                              label: widget.sellerName,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.sellerName,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      RatingStars(
                                        rating: _displaySellerRating,
                                        showValue: true,
                                      ),
                                      if (_sellerReviewCount > 0)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 6),
                                          child: Text(
                                            '($_sellerReviewCount)',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
