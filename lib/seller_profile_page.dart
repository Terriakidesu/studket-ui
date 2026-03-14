import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/profile_picture_api.dart';
import 'components/rating_stars.dart';
import 'components/studket_app_bar.dart';
import 'network_cached_image.dart';

class SellerProfilePage extends StatefulWidget {
  const SellerProfilePage({
    super.key,
    required this.sellerName,
    required this.sellerAvatarUrl,
    required this.sellerRating,
    this.sellerAccountId,
  });

  final String sellerName;
  final String sellerAvatarUrl;
  final double sellerRating;
  final int? sellerAccountId;

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  bool _isLoadingListings = false;
  bool _isLoadingReviews = false;
  bool _isSubmittingReview = false;
  bool _isLoadingProfile = false;
  String? _listingsError;
  String? _reviewsError;
  String? _reviewFormError;
  String? _profileError;
  List<_SellerListing> _listings = const <_SellerListing>[];
  List<_SellerReview> _reviews = const <_SellerReview>[];
  double? _derivedRating;
  _SellerProfileDetails? _profileDetails;
  String? _profilePictureUrl;
  String _reviewComment = '';
  int _reviewRating = 5;
  bool _hasCurrentUserReview = false;
  int _reviewFormVersion = 0;

  @override
  void initState() {
    super.initState();
    if (widget.sellerAccountId != null) {
      unawaited(_loadListings());
      unawaited(_loadReviews());
      unawaited(_loadProfile());
      unawaited(_loadProfilePicture());
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadListings() async {
    final int? accountId = widget.sellerAccountId;
    if (accountId == null) {
      return;
    }

    setState(() {
      _isLoadingListings = true;
      _listingsError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final http.Response response = await http
          .get(ApiRoutes.listingsForUser(accountId), headers: headers)
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      final List<_SellerListing> parsed = _parseListingsResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _listings = parsed;
      });
    } on TimeoutException {
      _setListingsError('Listings request timed out.');
    } on SocketException {
      _setListingsError('Could not connect to the listings API.');
    } on HttpException catch (error) {
      _setListingsError(error.message);
    } on FormatException {
      _setListingsError('Listings response format was invalid.');
    } catch (_) {
      _setListingsError('Failed to load listings.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingListings = false;
        });
      }
    }
  }

  List<_SellerListing> _parseListingsResponse(String body) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
            ? (decoded['items'] as List<dynamic>? ??
                decoded['results'] as List<dynamic>? ??
                decoded['data'] as List<dynamic>? ??
                const <dynamic>[])
            : const <dynamic>[];

    return items
        .whereType<Map<String, dynamic>>()
        .map(_SellerListing.fromJson)
        .toList(growable: false);
  }

  Future<void> _loadReviews() async {
    final int? accountId = widget.sellerAccountId;
    if (accountId == null) {
      return;
    }

    setState(() {
      _isLoadingReviews = true;
      _reviewsError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final http.Response response = await http
          .get(ApiRoutes.reviewsForUser(accountId), headers: headers)
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      final List<_SellerReview> parsed = _parseReviewsResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _reviews = parsed;
        _hasCurrentUserReview = _checkCurrentUserReview(parsed);
        _derivedRating = _computeAverageRating(parsed);
      });
    } on TimeoutException {
      _setReviewsError('Reviews request timed out.');
    } on SocketException {
      _setReviewsError('Could not connect to the reviews API.');
    } on HttpException catch (error) {
      _setReviewsError(error.message);
    } on FormatException {
      _setReviewsError('Reviews response format was invalid.');
    } catch (_) {
      _setReviewsError('Failed to load reviews.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReviews = false;
        });
      }
    }
  }

  Future<void> _loadProfile() async {
    final int? accountId = widget.sellerAccountId;
    if (accountId == null) {
      return;
    }

    setState(() {
      _isLoadingProfile = true;
      _profileError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final http.Response response = await http
          .get(ApiRoutes.profileById(accountId), headers: headers)
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Profile response was invalid.');
      }

      final _SellerProfileDetails parsed =
          _SellerProfileDetails.fromJson(decoded);
      if (!mounted) {
        return;
      }
      setState(() {
        _profileDetails = parsed;
      });
    } on TimeoutException {
      _setProfileError('Profile request timed out.');
    } on SocketException {
      _setProfileError('Could not connect to the profile API.');
    } on HttpException catch (error) {
      _setProfileError(error.message);
    } on FormatException {
      _setProfileError('Profile response format was invalid.');
    } catch (_) {
      _setProfileError('Failed to load seller profile.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _loadProfilePicture() async {
    final int? accountId = widget.sellerAccountId;
    if (accountId == null) {
      return;
    }

    try {
      final String? url = await ProfilePictureApi.resolveForAccount(accountId);
      if (!mounted) {
        return;
      }
      setState(() {
        _profilePictureUrl = url;
      });
    } catch (_) {
      // Ignore profile picture failures; fall back to provided avatar.
    }
  }

  bool _checkCurrentUserReview(List<_SellerReview> reviews) {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      return false;
    }
    return reviews.any((review) => review.reviewerId == accountId);
  }

  double? _computeAverageRating(List<_SellerReview> reviews) {
    if (reviews.isEmpty) {
      return null;
    }
    final int total = reviews.fold<int>(0, (sum, item) => sum + item.rating);
    return total / reviews.length;
  }

  double get _displayRating => _derivedRating ?? widget.sellerRating;

  List<_SellerReview> _parseReviewsResponse(String body) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
            ? (decoded['items'] as List<dynamic>? ?? const <dynamic>[])
            : const <dynamic>[];

    return items
        .whereType<Map<String, dynamic>>()
        .map(_SellerReview.fromJson)
        .toList(growable: false);
  }

  Future<void> _submitReview() async {
    final int? sellerId = widget.sellerAccountId;
    final int? reviewerId = ApiAuthSession.accountId;
    if (sellerId == null || reviewerId == null) {
      _setReviewFormError('You must be logged in to submit a review.');
      return;
    }

    if (_isSubmittingReview) {
      return;
    }

    setState(() {
      _isSubmittingReview = true;
      _reviewFormError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final Map<String, dynamic> payload = <String, dynamic>{
        'reviewer_id': reviewerId,
        'rating': _reviewRating,
      };

      final String comment = _reviewComment.trim();
      if (comment.isNotEmpty) {
        payload['comment'] = comment;
      }

      final http.Response response = await http
          .post(
            ApiRoutes.reviewsForSellerDirect(sellerId),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _reviewRating = 5;
        _reviewComment = '';
        _reviewFormVersion += 1;
      });
      await _loadReviews();
    } on TimeoutException {
      _setReviewFormError('Review submission timed out.');
    } on SocketException {
      _setReviewFormError('Could not connect to the reviews API.');
    } on HttpException catch (error) {
      _setReviewFormError(error.message);
    } on FormatException {
      _setReviewFormError('Review response format was invalid.');
    } catch (_) {
      _setReviewFormError('Failed to submit review.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
        });
      }
    }
  }

  Future<void> _editReview(_SellerReview review) async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      return;
    }

    final _ReviewEditResult? result = await showDialog<_ReviewEditResult>(
      context: context,
      builder: (context) => _EditReviewDialog(review: review),
    );

    if (result == null) {
      return;
    }
    final String comment = result.comment.trim();

    setState(() {
      _isSubmittingReview = true;
      _reviewFormError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final Map<String, dynamic> payload = <String, dynamic>{
        'rating': result.rating,
        'comment': comment,
      };

      final Uri target = ApiRoutes.reviewById(review.reviewId).replace(
        queryParameters: <String, String>{
          'account_id': '$accountId',
        },
      );

      final http.Response response = await http
          .patch(
            target,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractErrorMessage(response));
      }

      await _loadReviews();
    } on TimeoutException {
      _setReviewFormError('Review update timed out.');
    } on SocketException {
      _setReviewFormError('Could not connect to the reviews API.');
    } on HttpException catch (error) {
      _setReviewFormError(error.message);
    } on FormatException {
      _setReviewFormError('Review update response format was invalid.');
    } catch (_) {
      _setReviewFormError('Failed to update review.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
        });
      }
    }
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'] ?? decoded['message'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is Map<String, dynamic>) {
          final String? error = detail['error']?.toString();
          if (error != null && error.trim().isNotEmpty) {
            return error.trim();
          }
        }
      }
    } catch (_) {}
    return 'Request failed (HTTP ${response.statusCode}).';
  }

  void _setListingsError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _listingsError = message;
    });
  }

  void _setReviewsError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _reviewsError = message;
    });
  }

  void _setProfileError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _profileError = message;
    });
  }

  void _setReviewFormError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _reviewFormError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final String? profileAvatarUrl =
        _profilePictureUrl ??
        _profileDetails?.profilePhoto ??
        widget.sellerAvatarUrl;
    final String resolvedAvatarUrl =
        normalizeApiAssetUrl(profileAvatarUrl)?.trim() ?? '';
    final bool hasSellerAvatar = resolvedAvatarUrl.isNotEmpty;
    final bool hasSellerAccountId = widget.sellerAccountId != null;
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
                    backgroundImage:
                        hasSellerAvatar ? NetworkImage(resolvedAvatarUrl) : null,
                    child: hasSellerAvatar
                        ? null
                        : const Icon(Icons.storefront_outlined),
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
                        RatingStars(
                          rating: _displayRating,
                          showValue: true,
                        ),
                        const SizedBox(height: 8),
                        if (hasSellerAccountId)
                          _SellerProfileInfo(
                            isLoading: _isLoadingProfile,
                            errorMessage: _profileError,
                            details: _profileDetails,
                          )
                        else
                          Text(
                            'Seller account id is unavailable for listings and reviews.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[700],
                                ),
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
                  _SellerListingsTab(
                    hasAccountId: hasSellerAccountId,
                    isLoading: _isLoadingListings,
                    errorMessage: _listingsError,
                    listings: _listings,
                  ),
                  _SellerReviewsTab(
                    hasAccountId: hasSellerAccountId,
                    isLoading: _isLoadingReviews,
                    errorMessage: _reviewsError,
                    reviews: _reviews,
                    reviewFormError: _reviewFormError,
                    rating: _reviewRating,
                    comment: _reviewComment,
                    formVersion: _reviewFormVersion,
                    isSubmitting: _isSubmittingReview,
                    hasExistingReview: _hasCurrentUserReview,
                    showRatingSummary: ApiAuthSession.isSeller,
                    averageRating: _derivedRating,
                    onEditReview: _editReview,
                    onRatingChanged: (value) {
                      setState(() {
                        _reviewRating = value;
                      });
                    },
                    onCommentChanged: (value) {
                      setState(() {
                        _reviewComment = value;
                      });
                    },
                    onSubmit: _submitReview,
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

class _SellerListingsTab extends StatelessWidget {
  const _SellerListingsTab({
    required this.hasAccountId,
    required this.isLoading,
    required this.errorMessage,
    required this.listings,
  });

  final bool hasAccountId;
  final bool isLoading;
  final String? errorMessage;
  final List<_SellerListing> listings;

  @override
  Widget build(BuildContext context) {
    if (!hasAccountId) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Seller account id is required to load listings.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            errorMessage!,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (listings.isEmpty) {
      return const Center(
        child: Text('No listings yet.'),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: listings.length,
      itemBuilder: (context, index) {
        return _SellerListingCard(listing: listings[index]);
      },
    );
  }
}

class _SellerReviewsTab extends StatelessWidget {
  const _SellerReviewsTab({
    required this.hasAccountId,
    required this.isLoading,
    required this.errorMessage,
    required this.reviews,
    required this.reviewFormError,
    required this.rating,
    required this.comment,
    required this.formVersion,
    required this.isSubmitting,
    required this.hasExistingReview,
    required this.showRatingSummary,
    required this.averageRating,
    required this.onEditReview,
    required this.onRatingChanged,
    required this.onCommentChanged,
    required this.onSubmit,
  });

  final bool hasAccountId;
  final bool isLoading;
  final String? errorMessage;
  final List<_SellerReview> reviews;
  final String? reviewFormError;
  final int rating;
  final String comment;
  final int formVersion;
  final bool isSubmitting;
  final bool hasExistingReview;
  final bool showRatingSummary;
  final double? averageRating;
  final ValueChanged<_SellerReview> onEditReview;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onCommentChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (!hasAccountId) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'Seller account id is required to load reviews.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (showRatingSummary)
          _SellerRatingSummary(
            averageRating: averageRating,
            reviewCount: reviews.length,
          ),
        if (showRatingSummary) const SizedBox(height: 16),
        if (!hasExistingReview)
          _SellerReviewForm(
            rating: rating,
            comment: comment,
            formVersion: formVersion,
            isSubmitting: isSubmitting,
            errorMessage: reviewFormError,
            onRatingChanged: onRatingChanged,
            onCommentChanged: onCommentChanged,
            onSubmit: onSubmit,
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Text(
              'You have already left a review for this seller.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        const SizedBox(height: 16),
        if (isLoading)
          const Center(child: CircularProgressIndicator())
        else if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              errorMessage!,
              textAlign: TextAlign.center,
            ),
          )
        else if (reviews.isEmpty)
          const Center(child: Text('No reviews yet.'))
        else
          ...reviews.map(
            (_SellerReview review) => _SellerReviewCard(
              review: review,
              onEdit: onEditReview,
            ),
          ),
      ],
    );
  }
}

class _SellerRatingSummary extends StatelessWidget {
  const _SellerRatingSummary({
    required this.averageRating,
    required this.reviewCount,
  });

  final double? averageRating;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final double displayRating = averageRating ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.star_rounded,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            displayRating.toStringAsFixed(1),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($reviewCount reviews)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerReviewForm extends StatelessWidget {
  const _SellerReviewForm({
    required this.rating,
    required this.comment,
    required this.formVersion,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onRatingChanged,
    required this.onCommentChanged,
    required this.onSubmit,
  });

  final int rating;
  final String comment;
  final int formVersion;
  final bool isSubmitting;
  final String? errorMessage;
  final ValueChanged<int> onRatingChanged;
  final ValueChanged<String> onCommentChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leave a Review',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          _SellerReviewRatingPicker(
            rating: rating,
            onChanged: onRatingChanged,
          ),
          const SizedBox(height: 12),
          _SellerReviewCommentField(
            initialText: comment,
            formVersion: formVersion,
            onChanged: onCommentChanged,
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: isSubmitting ? null : onSubmit,
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Submit Review'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only completed transactions can be reviewed. Buyers only. '
            'The most recent completed transaction is used automatically.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerReviewRatingPicker extends StatelessWidget {
  const _SellerReviewRatingPicker({
    required this.rating,
    required this.onChanged,
  });

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rating',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (index) {
            final int value = index + 1;
            final bool isActive = value <= rating;
            return IconButton(
              onPressed: () => onChanged(value),
              icon: Icon(
                isActive ? Icons.star_rounded : Icons.star_border_rounded,
                color: isActive ? colorScheme.primary : colorScheme.outline,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SellerReviewCommentField extends StatefulWidget {
  const _SellerReviewCommentField({
    required this.initialText,
    required this.formVersion,
    required this.onChanged,
  });

  final String initialText;
  final int formVersion;
  final ValueChanged<String> onChanged;

  @override
  State<_SellerReviewCommentField> createState() =>
      _SellerReviewCommentFieldState();
}

class _SellerReviewCommentFieldState extends State<_SellerReviewCommentField> {
  late TextEditingController _controller;
  late int _lastVersion;

  @override
  void initState() {
    super.initState();
    _lastVersion = widget.formVersion;
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_handleChanged);
  }

  @override
  void didUpdateWidget(_SellerReviewCommentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.formVersion != _lastVersion ||
        widget.initialText != oldWidget.initialText) {
      _lastVersion = widget.formVersion;
      _controller
        ..removeListener(_handleChanged)
        ..dispose();
      _controller = TextEditingController(text: widget.initialText);
      _controller.addListener(_handleChanged);
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleChanged)
      ..dispose();
    super.dispose();
  }

  void _handleChanged() {
    widget.onChanged(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: 3,
      decoration: const InputDecoration(
        labelText: 'Comment (optional)',
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _EditReviewDialog extends StatefulWidget {
  const _EditReviewDialog({required this.review});

  final _SellerReview review;

  @override
  State<_EditReviewDialog> createState() => _EditReviewDialogState();
}

class _EditReviewDialogState extends State<_EditReviewDialog> {
  late TextEditingController _controller;
  late int _rating;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.review.comment);
    _rating = widget.review.rating;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Edit Review'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SellerReviewRatingPicker(
            rating: _rating,
            onChanged: (value) {
              setState(() {
                _rating = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comment (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only your own review can be edited.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _ReviewEditResult(
                rating: _rating,
                comment: _controller.text,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ReviewEditResult {
  const _ReviewEditResult({
    required this.rating,
    required this.comment,
  });

  final int rating;
  final String comment;
}

class _SellerListing {
  const _SellerListing({
    required this.id,
    required this.title,
    required this.description,
    required this.listingType,
    required this.status,
    required this.price,
    required this.budgetMin,
    required this.budgetMax,
    required this.tags,
    required this.primaryMediaUrl,
  });

  final int id;
  final String title;
  final String description;
  final String listingType;
  final String status;
  final num? price;
  final num? budgetMin;
  final num? budgetMax;
  final List<String> tags;
  final String? primaryMediaUrl;

  factory _SellerListing.fromJson(Map<String, dynamic> json) {
    return _SellerListing(
      id: (json['listing_id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? 'Untitled Listing').toString(),
      description: (json['description'] ?? '').toString(),
      listingType: (json['listing_type'] ?? '').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      price: json['price'] as num?,
      budgetMin: json['budget_min'] as num?,
      budgetMax: json['budget_max'] as num?,
      tags: _extractTags(json),
      primaryMediaUrl: _extractPrimaryMediaUrl(json),
    );
  }

  static List<String> _extractTags(Map<String, dynamic> json) {
    final dynamic raw = json['tags'];
    if (raw is List) {
      return raw.map((dynamic value) => value.toString()).toList(growable: false);
    }
    return const <String>[];
  }

  static String? _extractPrimaryMediaUrl(Map<String, dynamic> json) {
    final String? direct = normalizeApiAssetUrl(
      (json['primary_media_url'] ?? json['image_url'])?.toString(),
    );
    if (direct != null && direct.trim().isNotEmpty) {
      return direct;
    }

    final dynamic media = json['media'];
    if (media is List) {
      for (final dynamic item in media) {
        if (item is String) {
          final String? url = normalizeApiAssetUrl(item);
          if (url != null) {
            return url;
          }
        } else if (item is Map<String, dynamic>) {
          final String? url = normalizeApiAssetUrl(
            (item['file_url'] ?? item['url'] ?? item['media_url'])?.toString(),
          );
          if (url != null) {
            return url;
          }
        }
      }
    }

    return null;
  }
}

class _SellerListingCard extends StatelessWidget {
  const _SellerListingCard({required this.listing});

  final _SellerListing listing;

  String _formatMoney(num? value) {
    if (value == null) {
      return 'Price unavailable';
    }
    return value % 1 == 0
        ? 'PHP ${value.toStringAsFixed(0)}'
        : 'PHP ${value.toStringAsFixed(2)}';
  }

  String _formatListingAmount() {
    final String normalized = listing.listingType.trim().toLowerCase();
    if (normalized == 'looking_for' || normalized == 'looking for') {
      if (listing.budgetMin != null && listing.budgetMax != null) {
        return '${_formatMoney(listing.budgetMin)} - ${_formatMoney(listing.budgetMax)}';
      }
      return _formatMoney(listing.budgetMin);
    }
    return _formatMoney(listing.price);
  }

  bool _isLookingFor() {
    final String normalized = listing.listingType.trim().toLowerCase();
    return normalized == 'looking_for' || normalized == 'looking for';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isLookingFor = _isLookingFor();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ListingMediaThumbnail(url: listing.primaryMediaUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isLookingFor
                          ? colorScheme.tertiaryContainer
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isLookingFor
                              ? Icons.search_rounded
                              : Icons.inventory_2_outlined,
                          size: 14,
                          color: isLookingFor
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isLookingFor ? 'Looking For' : 'Listing',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isLookingFor
                                ? colorScheme.onTertiaryContainer
                                : colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatListingAmount(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  listing.status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingMediaThumbnail extends StatelessWidget {
  const _ListingMediaThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 64,
        height: 64,
        color: colorScheme.surfaceContainerHigh,
        child: url == null || url!.trim().isEmpty
            ? Icon(
                Icons.image_outlined,
                color: colorScheme.onSurfaceVariant,
              )
            : NetworkCachedImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                width: 64,
                height: 64,
              ),
      ),
    );
  }
}

class _SellerReview {
  const _SellerReview({
    required this.reviewId,
    required this.rating,
    required this.comment,
    required this.createdAt,
    required this.reviewerUsername,
    required this.reviewerId,
  });

  final int reviewId;
  final int rating;
  final String comment;
  final DateTime? createdAt;
  final String reviewerUsername;
  final int reviewerId;

  factory _SellerReview.fromJson(Map<String, dynamic> json) {
    return _SellerReview(
      reviewId: (json['review_id'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: (json['comment'] as String?)?.trim() ?? '',
      createdAt: _parseDate(json['created_at']),
      reviewerUsername: (json['reviewer_username'] as String?)?.trim() ??
          (json['reviewer_name'] as String?)?.trim() ??
          'Reviewer',
      reviewerId: (json['reviewer_id'] as num?)?.toInt() ?? 0,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class _SellerReviewCard extends StatelessWidget {
  const _SellerReviewCard({
    required this.review,
    required this.onEdit,
  });

  final _SellerReview review;
  final ValueChanged<_SellerReview> onEdit;

  String _formatDate(DateTime? value) {
    if (value == null) {
      return '';
    }
    final DateTime local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final int? accountId = ApiAuthSession.accountId;
    final bool canEdit = accountId != null && accountId == review.reviewerId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _maskUsername(review.reviewerUsername),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              if (canEdit) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Edit review',
                  onPressed: () => onEdit(review),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
              const Spacer(),
              Text(
                _formatDate(review.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canEdit ? () => onEdit(review) : null,
            child: Row(
              children: List.generate(5, (index) {
                final bool isActive = index < review.rating;
                return Icon(
                  isActive ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 18,
                  color: isActive ? colorScheme.primary : colorScheme.outline,
                );
              }),
            ),
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _maskUsername(String username) {
    final String trimmed = username.trim();
    if (trimmed.isEmpty) {
      return 'User';
    }
    if (trimmed.length <= 2) {
      return '${trimmed[0]}**';
    }
    final int stars = trimmed.length - 2;
    return '${trimmed.substring(0, 2)}${'*' * stars}';
  }
}

class _SellerProfileInfo extends StatelessWidget {
  const _SellerProfileInfo({
    required this.isLoading,
    required this.errorMessage,
    required this.details,
  });

  final bool isLoading;
  final String? errorMessage;
  final _SellerProfileDetails? details;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          errorMessage!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.error,
          ),
        ),
      );
    }

    final _SellerProfileDetails? profile = details;
    if (profile == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'Profile details are unavailable.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (profile.fullName.isNotEmpty)
            _ProfileInfoRow(label: 'Name', value: profile.fullName),
          if (profile.campus.isNotEmpty)
            _ProfileInfoRow(label: 'Campus', value: profile.campus),
          if (profile.email.isNotEmpty)
            _ProfileInfoRow(label: 'Email', value: profile.email),
        ],
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerProfileDetails {
  const _SellerProfileDetails({
    required this.firstName,
    required this.lastName,
    required this.campus,
    required this.email,
    required this.profilePhoto,
  });

  final String firstName;
  final String lastName;
  final String campus;
  final String email;
  final String profilePhoto;

  String get fullName {
    final String combined = '$firstName $lastName'.trim();
    return combined.replaceAll(RegExp(r'\s+'), ' ');
  }

  factory _SellerProfileDetails.fromJson(Map<String, dynamic> json) {
    return _SellerProfileDetails(
      firstName: (json['first_name'] as String?)?.trim() ??
          (json['seller_first_name'] as String?)?.trim() ??
          '',
      lastName: (json['last_name'] as String?)?.trim() ??
          (json['seller_last_name'] as String?)?.trim() ??
          '',
      campus: (json['campus'] as String?)?.trim() ??
          (json['seller_campus'] as String?)?.trim() ??
          '',
      email: (json['email'] as String?)?.trim() ??
          (json['seller_email'] as String?)?.trim() ??
          '',
      profilePhoto: (json['profile_photo'] as String?)?.trim() ??
          (json['seller_profile_photo'] as String?)?.trim() ??
          '',
    );
  }
}
