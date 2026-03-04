import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_base_url.dart';
import 'api_routes.dart';
import 'product_details_page.dart';
import 'components/product_grid_card.dart';
import 'components/rating_stars.dart';
import 'components/studket_app_bar.dart';

class SellerProfilePage extends StatefulWidget {
  const SellerProfilePage({
    super.key,
    required this.sellerName,
    required this.sellerAvatarUrl,
    required this.sellerRating,
  });

  final String sellerName;
  final String sellerAvatarUrl;
  final double sellerRating;

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  bool _isLoadingProducts = true;
  String? _productsError;
  List<_SellerProduct> _products = const <_SellerProduct>[];

  final List<_SellerReview> _reviews = <_SellerReview>[
    _SellerReview(
      reviewer: 'Noah Reyes',
      comment: 'Smooth transaction and item matched the description.',
      time: '2 days ago',
      rating: 5,
      sellerReply: 'Thank you for the smooth deal too.',
    ),
    _SellerReview(
      reviewer: 'Emma Gray',
      comment: 'Fast replies and very friendly seller.',
      time: '1 week ago',
      rating: 4,
    ),
    _SellerReview(
      reviewer: 'Liam Carter',
      comment: 'Great price and easy pick-up.',
      time: '2 weeks ago',
      rating: 5,
    ),
  ];

  final TextEditingController _reviewController = TextEditingController();
  int _newReviewRating = 5;

  bool get _hasUserReview =>
      _reviews.any((review) => review.reviewer.trim().toLowerCase() == 'you');

  @override
  void initState() {
    super.initState();
    _fetchSellerProducts();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _fetchSellerProducts() async {
    setState(() {
      _isLoadingProducts = true;
      _productsError = null;
    });

    try {
      final Uri uri = ApiRoutes.products(port: 8000);
      final http.Response response = await http
          .get(uri)
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('Products response is not a list');
      }

      final List<_SellerProduct> parsed = decoded
          .whereType<Map>()
          .map(
            (item) => _SellerProduct.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _products = parsed;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _productsError = 'Request timed out. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _productsError = 'Failed to load products.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProducts = false;
        });
      }
    }
  }

  void _addReview() {
    if (_hasUserReview) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can only post one review.')),
      );
      return;
    }
    final String text = _reviewController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _reviews.insert(
        0,
        _SellerReview(
          reviewer: 'You',
          comment: text,
          time: 'Just now',
          rating: _newReviewRating,
        ),
      );
      _reviewController.clear();
      _newReviewRating = 5;
    });
  }

  Future<void> _replyToReview(int index) async {
    String replyDraft = '';
    final String? reply = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reply to review'),
          content: TextField(
            maxLines: 3,
            onChanged: (value) {
              replyDraft = value;
            },
            decoration: const InputDecoration(
              hintText: 'Write a seller reply',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(replyDraft.trim()),
              child: const Text('Reply'),
            ),
          ],
        );
      },
    );

    if (!mounted || reply == null || reply.isEmpty) return;
    setState(() {
      _reviews[index] = _reviews[index].copyWith(sellerReply: reply);
    });
  }

  Future<void> _editUserReview(int index) async {
    final _SellerReview review = _reviews[index];
    String editText = review.comment;
    int editRating = review.rating;

    final (String, int)? result = await showDialog<(String, int)>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit your review'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(5, (starIndex) {
                        final int star = starIndex + 1;
                        return IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setDialogState(() {
                              editRating = star;
                            });
                          },
                          icon: Icon(
                            star <= editRating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: Colors.amber[700],
                          ),
                        );
                      }),
                    ),
                    TextFormField(
                      initialValue: review.comment,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (value) {
                        editText = value;
                      },
                      decoration: const InputDecoration(
                        hintText: 'Update your review',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final String updatedText = editText.trim();
                    if (updatedText.isEmpty) return;
                    Navigator.of(context).pop((updatedText, editRating));
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted || result == null) return;

    setState(() {
      _reviews[index] = review.copyWith(
        comment: result.$1,
        rating: result.$2,
        time: 'Edited just now',
      );
    });
  }

  void _openProductDetails(_SellerProduct product, int index) {
    final String seed = product.name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(',', '');
    final List<String> gallery = List.generate(
      4,
      (i) => 'https://picsum.photos/seed/${seed}_${index}_$i/900',
    );

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
          productName: product.name,
          productPrice: product.priceLabel,
          productLocation: product.location,
          productDescription: product.description,
          imageUrls: gallery,
          sellerName: widget.sellerName,
          sellerAvatarUrl: widget.sellerAvatarUrl,
          sellerRating: widget.sellerRating,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: const StudketAppBar(title: 'Seller Profile'),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage: NetworkImage(widget.sellerAvatarUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sellerName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            RatingStars(
                              rating: widget.sellerRating,
                              showValue: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TabBar(
              tabs: const [
                Tab(text: 'Products'),
                Tab(text: 'Reviews'),
              ],
              labelColor: Theme.of(context).colorScheme.primary,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  Builder(
                    builder: (context) {
                      if (_isLoadingProducts) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (_productsError != null && _products.isEmpty) {
                        return Center(child: Text(_productsError!));
                      }

                      if (_products.isEmpty) {
                        return const Center(child: Text('No products found.'));
                      }

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _products.length,
                        gridDelegate: kProductGridDelegate,
                        itemBuilder: (context, index) {
                          final item = _products[index];
                          return ProductGridCard(
                            name: item.name,
                            price: item.priceLabel,
                            location: item.location,
                            imageUrl: item.imageUrl,
                            onTap: () => _openProductDetails(item, index),
                          );
                        },
                      );
                    },
                  ),
                  Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _reviews.length,
                          itemBuilder: (context, index) {
                            final review = _reviews[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              review.reviewer,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            review.time,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Colors.grey[600],
                                                ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      RatingStars(
                                        rating: review.rating.toDouble(),
                                        starSize: 17,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(review.comment),
                                      if (review.reviewer
                                              .trim()
                                              .toLowerCase() ==
                                          'you')
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () =>
                                                _editUserReview(index),
                                            child: const Text('Edit review'),
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      if (review.sellerReply != null)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Seller reply',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(review.sellerReply!),
                                            ],
                                          ),
                                        )
                                      else
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () =>
                                                _replyToReview(index),
                                            child: const Text(
                                              'Reply as seller',
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      if (!_hasUserReview)
                        SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Write a review',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: List.generate(5, (index) {
                                      final int star = index + 1;
                                      return IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () {
                                          setState(() {
                                            _newReviewRating = star;
                                          });
                                        },
                                        icon: Icon(
                                          star <= _newReviewRating
                                              ? Icons.star_rounded
                                              : Icons.star_border_rounded,
                                          color: Colors.amber[700],
                                        ),
                                      );
                                    }),
                                  ),
                                  TextField(
                                    controller: _reviewController,
                                    minLines: 2,
                                    maxLines: 4,
                                    decoration: const InputDecoration(
                                      hintText: 'Share your experience',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton(
                                      onPressed: _addReview,
                                      child: const Text('Post Review'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellerReview {
  const _SellerReview({
    required this.reviewer,
    required this.comment,
    required this.time,
    required this.rating,
    this.sellerReply,
  });

  final String reviewer;
  final String comment;
  final String time;
  final int rating;
  final String? sellerReply;

  _SellerReview copyWith({
    String? reviewer,
    String? comment,
    String? time,
    int? rating,
    String? sellerReply,
  }) {
    return _SellerReview(
      reviewer: reviewer ?? this.reviewer,
      comment: comment ?? this.comment,
      time: time ?? this.time,
      rating: rating ?? this.rating,
      sellerReply: sellerReply ?? this.sellerReply,
    );
  }
}

class _SellerProduct {
  const _SellerProduct({
    required this.name,
    required this.priceLabel,
    required this.location,
    required this.imageUrl,
    required this.description,
  });

  final String name;
  final String priceLabel;
  final String location;
  final String imageUrl;
  final String description;

  factory _SellerProduct.fromJson(Map<String, dynamic> json) {
    final String name = (json['name'] ?? json['title'] ?? 'Untitled Product')
        .toString();
    final String location =
        (json['location'] ?? json['address'] ?? 'Location unavailable')
            .toString();
    final String imageUrl =
        (json['image'] ??
                json['image_url'] ??
                json['thumbnail'] ??
                'https://picsum.photos/seed/default_seller_product/300')
            .toString();
    final String description =
        (json['description'] ??
                '$name in excellent condition. Message the seller for details.')
            .toString();

    return _SellerProduct(
      name: name,
      priceLabel: _formatPeso(json['price']),
      location: location,
      imageUrl: imageUrl,
      description: description,
    );
  }

  static String _formatPeso(dynamic rawPrice) {
    if (rawPrice is num) {
      final String amount = rawPrice % 1 == 0
          ? rawPrice.toStringAsFixed(0)
          : rawPrice.toStringAsFixed(2);
      return '₱$amount';
    }

    final String text = (rawPrice ?? '').toString().trim();
    if (text.isEmpty) return '₱0';

    final String numeric = text.replaceAll(RegExp(r'[^0-9.]'), '');
    final num? parsed = num.tryParse(numeric);
    if (parsed == null) return '₱0';

    final String amount = parsed % 1 == 0
        ? parsed.toStringAsFixed(0)
        : parsed.toStringAsFixed(2);
    return '₱$amount';
  }
}
