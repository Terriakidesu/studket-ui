import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme_controller.dart';
import 'app_entry_page.dart';
import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/profile_picture_api.dart';
import 'api/api_routes.dart';
import 'api/api_session_storage.dart';
import 'api/auth_api.dart';
import 'api/user_realtime_service.dart';
import 'components/account_avatar.dart';
import 'components/rating_stars.dart';
import 'listing_editor_page.dart';
import 'network_cached_image.dart';
import 'seller_profile_page.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final ImagePicker _imagePicker = ImagePicker();

  bool _isElevatingSeller = false;
  bool _isSubmittingTrustedSellerRequest = false;
  bool _isUploadingProfilePicture = false;
  bool _isLoggingOut = false;
  bool _isLoadingMyPosts = false;
  String? _myPostsError;
  List<_ProfileListing> _activeListings = const <_ProfileListing>[];
  List<_ProfileListing> _lookingForPosts = const <_ProfileListing>[];
  bool _isLoadingSellerRating = false;
  String? _sellerRatingError;
  double? _sellerAverageRating;
  int _sellerReviewCount = 0;

  @override
  void initState() {
    super.initState();
    if (ApiAuthSession.isSeller) {
      unawaited(_loadMyPosts());
      unawaited(_loadSellerRating());
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _requestTrustedSeller() async {
    setState(() {
      _isSubmittingTrustedSellerRequest = true;
    });

    try {
      await AuthApi.requestSellerStatus(
        submissionNote: 'Requested from the Flutter marketplace app.',
      );
      _showMessage('Trusted seller verification request submitted.');
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Failed to submit trusted seller request.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingTrustedSellerRequest = false;
        });
        await _loadMyPosts();
      }
    }
  }

  Future<void> _elevateToSeller() async {
    setState(() {
      _isElevatingSeller = true;
    });

    try {
      await AuthApi.elevateToSeller();
      _showMessage('Your account is now a seller account.');
      await _loadMyPosts();
    } on TimeoutException {
      _showMessage('Request timed out. Please try again.');
    } on SocketException {
      _showMessage('No internet connection. Check your network and try again.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Failed to elevate account to seller.');
    } finally {
      if (mounted) {
        setState(() {
          _isElevatingSeller = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    if (_isLoggingOut) {
      return;
    }

    setState(() {
      _isLoggingOut = true;
    });

    await UserRealtimeService.instance.disconnect(clearState: true);
    await ApiSessionStorage.clear();
    ApiAuthSession.clear();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppEntryPage()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _showProfilePictureActions() async {
    if (_isUploadingProfilePicture) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take Photo'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _pickAndUploadProfilePicture(ImageSource.camera);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Upload from Gallery'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _pickAndUploadProfilePicture(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadProfilePicture(ImageSource source) async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null || _isUploadingProfilePicture) {
      return;
    }

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 92,
      );
      if (picked == null) {
        return;
      }

      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: <PlatformUiSettings>[
          AndroidUiSettings(
            toolbarTitle: 'Crop Profile Picture',
            toolbarColor: const Color(0xFF5865F2),
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            activeControlsWidgetColor: const Color(0xFF5865F2),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: false,
            cropStyle: CropStyle.rectangle,
          ),
          IOSUiSettings(
            title: 'Crop Profile Picture',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            aspectRatioPickerButtonHidden: true,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
            cropStyle: CropStyle.rectangle,
          ),
        ],
      );
      if (cropped == null) {
        return;
      }

      setState(() {
        _isUploadingProfilePicture = true;
      });

      await ProfilePictureApi.uploadForAccount(
        accountId: accountId,
        file: File(cropped.path),
      );

      if (!mounted) {
        return;
      }
      setState(() {});
      _showMessage('Profile picture updated.');
    } on TimeoutException {
      _showMessage('Profile picture upload timed out.');
    } on SocketException {
      _showMessage('Could not connect to the profile picture service.');
    } on HttpException catch (error) {
      _showMessage(error.message);
    } catch (_) {
      _showMessage('Failed to update profile picture.');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingProfilePicture = false;
        });
      }
    }
  }

  Future<void> _loadMyPosts() async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null || !ApiAuthSession.isSeller) {
      return;
    }

    setState(() {
      _isLoadingMyPosts = true;
      _myPostsError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final Future<http.Response> listingsRequest = http
          .get(ApiRoutes.listingsForUser(accountId), headers: headers)
          .timeout(kApiRequestTimeout);
      final Future<http.Response> lookingForRequest = http
          .get(ApiRoutes.lookingForListingsForUser(accountId), headers: headers)
          .timeout(kApiRequestTimeout);

      final List<http.Response> responses = await Future.wait(<Future<http.Response>>[
        listingsRequest,
        lookingForRequest,
      ]);

      final http.Response listingsResponse = responses[0];
      final http.Response lookingForResponse = responses[1];

      if (listingsResponse.statusCode < 200 || listingsResponse.statusCode >= 300) {
        throw HttpException(_extractPostsError(listingsResponse));
      }
      if (lookingForResponse.statusCode < 200 || lookingForResponse.statusCode >= 300) {
        throw HttpException(_extractPostsError(lookingForResponse));
      }

      final List<_ProfileListing> listings = _parseProfileListingsResponse(
        listingsResponse.body,
        accountId,
        label: 'listings',
      ).where(
        (_ProfileListing item) => _isActiveStatus(item.status),
      ).toList(growable: false);

      final List<_ProfileListing> lookingFor = _parseProfileListingsResponse(
        lookingForResponse.body,
        accountId,
        label: 'looking-for',
      ).where(
        (_ProfileListing item) => _isActiveStatus(item.status),
      ).toList(growable: false);

      if (!mounted) {
        return;
      }
      setState(() {
        _activeListings = listings;
        _lookingForPosts = lookingFor;
      });
    } on TimeoutException {
      _setMyPostsError('Posts request timed out.');
    } on SocketException {
      _setMyPostsError('Could not connect to the listings API.');
    } on HttpException catch (error) {
      _setMyPostsError(error.message);
    } on FormatException {
      _setMyPostsError('Posts response format was invalid.');
    } catch (_) {
      _setMyPostsError('Failed to load your posts.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMyPosts = false;
        });
      }
    }
  }

  Future<void> _loadSellerRating() async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      return;
    }

    setState(() {
      _isLoadingSellerRating = true;
      _sellerRatingError = null;
    });

    try {
      final http.Response response = await http
          .get(
            ApiRoutes.reviewsForUser(accountId),
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractPostsError(response));
      }

      final List<int> ratings = _parseSellerRatings(response.body);
      if (!mounted) {
        return;
      }
      if (ratings.isEmpty) {
        setState(() {
          _sellerAverageRating = null;
          _sellerReviewCount = 0;
        });
        return;
      }
      final int total = ratings.fold<int>(0, (sum, value) => sum + value);
      setState(() {
        _sellerReviewCount = ratings.length;
        _sellerAverageRating = total / ratings.length;
      });
    } on TimeoutException {
      _sellerRatingError = 'Ratings request timed out.';
    } on SocketException {
      _sellerRatingError = 'Could not connect to the reviews API.';
    } on HttpException catch (error) {
      _sellerRatingError = error.message;
    } on FormatException {
      _sellerRatingError = 'Ratings response format was invalid.';
    } catch (_) {
      _sellerRatingError = 'Failed to load seller ratings.';
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSellerRating = false;
        });
      }
    }
  }

  List<int> _parseSellerRatings(String body) {
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

  void _setMyPostsError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _myPostsError = message;
    });
  }

  String _extractPostsError(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'] ?? decoded['message'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {}
    return 'Posts request failed (HTTP ${response.statusCode}).';
  }

  List<_ProfileListing> _parseProfileListingsResponse(
    String body,
    int accountId,
    {required String label}
  ) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
        ? (decoded['items'] as List<dynamic>? ??
              decoded['results'] as List<dynamic>? ??
              decoded['data'] as List<dynamic>? ??
              const <dynamic>[])
        : const <dynamic>[];

    final List<_ProfileListing> parsed = items
        .whereType<Map<String, dynamic>>()
        .map(_ProfileListing.fromJson)
        .where((item) => item.ownerId == null || item.ownerId == accountId)
        .toList(growable: false);

    return parsed;
  }

  bool _isActiveStatus(String status) {
    const Set<String> inactive = <String>{
      'sold',
      'archived',
      'deleted',
      'inactive',
      'cancelled',
      'closed',
    };
    return !inactive.contains(status.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String username = ApiAuthSession.username ?? 'studket_user';
    final String email = ApiAuthSession.email ?? 'No email';
    final String accountType = ApiAuthSession.accountType ?? 'user';
    final String marketplaceRole = ApiAuthSession.marketplaceRole ?? 'buyer';
    final bool isSeller = ApiAuthSession.isSeller;
    final bool isTrustedSeller = ApiAuthSession.trustedSeller;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AccountAvatar(
                              accountId: ApiAuthSession.accountId,
                              radius: 42,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              label: username,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Material(
                                color: theme.colorScheme.primary,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _isUploadingProfilePicture
                                      ? null
                                      : _showProfilePictureActions,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _isUploadingProfilePicture
                                        ? SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: theme.colorScheme.onPrimary,
                                            ),
                                          )
                                        : Icon(
                                            Icons.camera_alt_outlined,
                                            size: 14,
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    username,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DiscordTag(
                        label: _capitalize(accountType),
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        foregroundColor: theme.colorScheme.onSecondaryContainer,
                      ),
                      _DiscordTag(
                        label: _capitalize(marketplaceRole),
                        backgroundColor: isSeller
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: isSeller
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      _DiscordTag(
                        label: isTrustedSeller
                            ? 'Trusted Seller'
                            : 'Not Trusted Yet',
                        backgroundColor: isTrustedSeller
                            ? theme.colorScheme.tertiaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: isTrustedSeller
                            ? theme.colorScheme.onTertiaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DiscordSectionCard(
              title: 'Account',
              child: Column(
                children: [
                  _ActionRow(
                    icon: Icons.manage_accounts_outlined,
                    label: 'Account Settings',
                    value: 'Profile details, account info, and security',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountSettingsPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 24),
                  _ActionRow(
                    icon: Icons.receipt_long_outlined,
                    label: 'Transaction History',
                    value: 'Recent purchases, refunds, and order statuses',
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const TransactionHistoryPage(),
                        ),
                      );
                    },
                  ),
                  if (!isSeller) ...[
                    const Divider(height: 24),
                    _ActionRow(
                      icon: Icons.storefront_outlined,
                      label: _isElevatingSeller
                          ? 'Becoming Seller...'
                          : 'Become a Seller',
                      value: 'Elevate your buyer account to post listings',
                      onTap: _isElevatingSeller ? null : _elevateToSeller,
                    ),
                  ],
                ],
              ),
            ),
            if (isSeller) ...[
              const SizedBox(height: 16),
              _DiscordSectionCard(
                title: 'Seller Status',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isTrustedSeller
                            ? theme.colorScheme.tertiaryContainer
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isTrustedSeller
                                ? Icons.verified_rounded
                                : Icons.storefront_rounded,
                            color: isTrustedSeller
                                ? theme.colorScheme.onTertiaryContainer
                                : theme.colorScheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isTrustedSeller
                                  ? 'Your account already has trusted seller status.'
                                  : 'You are already a seller. You can now request trusted seller review.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: _isLoadingSellerRating
                          ? const Center(child: CircularProgressIndicator())
                          : _sellerRatingError != null
                              ? Text(
                                  _sellerRatingError!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                  ),
                                )
                              : _sellerReviewCount == 0
                                  ? Text(
                                      'No seller reviews yet.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Row(
                                      children: [
                                        RatingStars(
                                          rating: _sellerAverageRating ?? 0,
                                          showValue: true,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '($_sellerReviewCount)',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _isSubmittingTrustedSellerRequest ||
                                isTrustedSeller
                            ? null
                            : _requestTrustedSeller,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: theme.colorScheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSubmittingTrustedSellerRequest
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                isTrustedSeller
                                    ? 'Trusted Seller Active'
                                    : 'Request Trusted Seller',
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _DiscordSectionCard(
                title: 'Your Posts',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Manage what is currently live on your seller account.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh posts',
                          onPressed: _isLoadingMyPosts ? null : _loadMyPosts,
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                    if (_isLoadingMyPosts)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_myPostsError != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: theme.colorScheme.error.withValues(alpha: 0.28),
                          ),
                        ),
                        child: Text(
                          _myPostsError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      )
                    else ...[
                      _PostsGroup(
                        title: 'Current Listings',
                        emptyLabel: 'No active listings yet.',
                        items: _activeListings,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _PostsListPage(
                                title: 'Current Listings',
                                emptyLabel: 'No active listings yet.',
                                items: _activeListings,
                                onEdit: _editProfileListing,
                              ),
                            ),
                          );
                        },
                        onEdit: _editProfileListing,
                      ),
                      const SizedBox(height: 16),
                      _PostsGroup(
                        title: 'Looking For Posts',
                        emptyLabel: 'No active looking for posts yet.',
                        items: _lookingForPosts,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _PostsListPage(
                                title: 'Looking For Posts',
                                emptyLabel: 'No active looking for posts yet.',
                                items: _lookingForPosts,
                                onEdit: _editProfileListing,
                              ),
                            ),
                          );
                        },
                        onEdit: _editProfileListing,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            _DiscordSectionCard(
              title: 'Settings',
              child: Column(
                children: [
                  const _ActionRow(
                    icon: Icons.shield_outlined,
                    label: 'Saved Session',
                    value: 'Active on this device',
                  ),
                  const Divider(height: 24),
                  AnimatedBuilder(
                    animation: AppThemeController.instance,
                    builder: (BuildContext context, _) {
                      return _ActionRow(
                        icon: Icons.dark_mode_outlined,
                        label: 'Appearance',
                        value: _themePreferenceLabel(
                          AppThemeController.instance.themeMode,
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AppearanceSettingsPage(),
                            ),
                          );
                        },
                      );
                    },
                  ),
                  if (kDebugMode) ...<Widget>[
                    const Divider(height: 24),
                    _ActionRow(
                      icon: Icons.developer_mode_outlined,
                      label: 'Debug Settings',
                      value: 'Development-only configuration',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const DebugSettingsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                  const Divider(height: 24),
                  _ActionRow(
                    icon: Icons.logout_rounded,
                    label: 'Log Out',
                    value: 'Clear local session and disconnect',
                    danger: true,
                    onTap: _isLoggingOut ? null : _logout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }

  String _themePreferenceLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light mode';
      case ThemeMode.dark:
        return 'Dark mode';
      case ThemeMode.system:
        return 'Follow device';
    }
  }

  Future<void> _editProfileListing(_ProfileListing item) async {
    final ListingEditorResult? result =
        await Navigator.of(context).push<ListingEditorResult>(
      MaterialPageRoute(
        builder: (_) => ListingEditorPage(
          initialListing: ListingEditorDraft(
            listingId: item.id,
            title: item.title,
            description: item.description,
            listingType: item.listingType,
            status: item.status,
            price: item.price,
            budgetMin: item.budgetMin,
            budgetMax: item.budgetMax,
            condition: item.condition,
            tags: item.tags,
          ),
        ),
      ),
    );
    if (result != null) {
      await _loadMyPosts();
      if (!mounted) {
        return;
      }
      _showMessage(
        result == ListingEditorResult.deleted
            ? 'Post deleted.'
            : 'Post updated.',
      );
    }
  }
}

class _ProfileListing {
  const _ProfileListing({
    required this.id,
    required this.shareToken,
    required this.shareUrl,
    required this.title,
    required this.description,
    required this.listingType,
    required this.status,
    required this.price,
    required this.budgetMin,
    required this.budgetMax,
    required this.condition,
    required this.ownerId,
    required this.tags,
  });

  final int id;
  final String? shareToken;
  final String? shareUrl;
  final String title;
  final String description;
  final String listingType;
  final String status;
  final num? price;
  final num? budgetMin;
  final num? budgetMax;
  final String? condition;
  final int? ownerId;
  final List<String> tags;

  factory _ProfileListing.fromJson(Map<String, dynamic> json) {
    return _ProfileListing(
      id: (json['listing_id'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      shareToken: (json['share_token'] ?? '').toString().trim().isEmpty
          ? null
          : (json['share_token'] ?? '').toString().trim(),
      shareUrl: normalizeApiAssetUrl((json['share_url'] ?? '').toString()),
      title: (json['title'] ?? 'Untitled Listing').toString(),
      description: (json['description'] ?? '').toString(),
      listingType: (json['listing_type'] ?? 'listing').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      price: json['price'] as num?,
      budgetMin: json['budget_min'] as num?,
      budgetMax: json['budget_max'] as num?,
      condition: json['condition']?.toString(),
      ownerId: (json['owner_id'] as num?)?.toInt() ??
          (json['seller_id'] as num?)?.toInt() ??
          (json['account_id'] as num?)?.toInt(),
      tags: (json['tags'] is List)
          ? (json['tags'] as List<dynamic>)
                .map((dynamic value) => value.toString())
                .toList(growable: false)
          : const <String>[],
    );
  }
}

class _DiscordSectionCard extends StatelessWidget {
  const _DiscordSectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DiscordTag extends StatelessWidget {
  const _DiscordTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.value,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color color = danger ? colorScheme.error : colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: danger
                    ? colorScheme.errorContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }
}

class _PostsGroup extends StatelessWidget {
  const _PostsGroup({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.onTap,
    required this.onEdit,
  });

  final String title;
  final String emptyLabel;
  final List<_ProfileListing> items;
  final VoidCallback onTap;
  final ValueChanged<_ProfileListing> onEdit;

  static const int _previewCount = 1;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool hasMoreThanPreview = items.length > _previewCount;
    final List<_ProfileListing> visibleItems = items
        .take(_previewCount)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: items.isEmpty ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (items.isNotEmpty)
                  Text(
                    hasMoreThanPreview
                        ? 'Recent ${visibleItems.length} of ${items.length}'
                        : '${items.length} item${items.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Text(
              emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else ...[
          ...visibleItems.map(
            (_ProfileListing item) =>
                _ProfileListingCard(item: item, onEdit: onEdit),
          ),
          if (hasMoreThanPreview)
            TextButton(
              onPressed: onTap,
              child: Text('Show all ${items.length}'),
            ),
        ],
      ],
    );
  }
}

class _PostsListPage extends StatelessWidget {
  const _PostsListPage({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.onEdit,
  });

  final String title;
  final String emptyLabel;
  final List<_ProfileListing> items;
  final ValueChanged<_ProfileListing> onEdit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                emptyLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ...items.map(
              (_ProfileListing item) =>
                  _ProfileListingCard(item: item, onEdit: onEdit),
            ),
        ],
      ),
    );
  }
}

class _ProfileListingCard extends StatelessWidget {
  const _ProfileListingCard({
    required this.item,
    required this.onEdit,
  });

  final _ProfileListing item;
  final ValueChanged<_ProfileListing> onEdit;

  String _formatMoney(num? value) {
    if (value == null) {
      return 'Budget unavailable';
    }
    return value % 1 == 0
        ? 'PHP ${value.toStringAsFixed(0)}'
        : 'PHP ${value.toStringAsFixed(2)}';
  }

  String _formatListingAmount(_ProfileListing item) {
    if (item.listingType == 'looking_for') {
      if (item.budgetMin != null && item.budgetMax != null) {
        return '${_formatMoney(item.budgetMin)} - ${_formatMoney(item.budgetMax)}';
      }
      return _formatMoney(item.budgetMin ?? item.price);
    }
    return _formatMoney(item.price).replaceFirst('Budget', 'Price');
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatListingAmount(item),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(item.status),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Edit post',
                  onPressed: () {
                    onEdit(item);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.description.trim().isEmpty
                  ? 'No description provided.'
                  : item.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ProfileMetaPill(
                  icon: Icons.category_outlined,
                  label: item.listingType,
                ),
                if ((item.condition ?? '').trim().isNotEmpty)
                  _ProfileMetaPill(
                    icon: Icons.fact_check_outlined,
                    label: item.condition!,
                  ),
                if (item.tags.isNotEmpty)
                  ...item.tags.map(
                    (String tag) => Chip(
                      label: Text(tag),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileMetaPill extends StatelessWidget {
  const _ProfileMetaPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: colorScheme.surfaceContainerHighest,
      labelStyle: theme.textTheme.labelSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class AccountSettingsPage extends StatelessWidget {
  const AccountSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String username = ApiAuthSession.username ?? 'studket_user';
    final String email = ApiAuthSession.email ?? 'No email';
    final String accountType = ApiAuthSession.accountType ?? 'user';
    final String marketplaceRole = ApiAuthSession.marketplaceRole ?? 'buyer';

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiscordSectionCard(
            title: 'Profile',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SettingInfoLine(
                  label: 'Account ID',
                  value: '${ApiAuthSession.accountId ?? '-'}',
                ),
                _SettingInfoLine(label: 'Username', value: username),
                _SettingInfoLine(label: 'Email', value: email),
                _SettingInfoLine(label: 'Account Type', value: accountType),
                _SettingInfoLine(
                  label: 'Marketplace Role',
                  value: marketplaceRole,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DiscordSectionCard(
            title: 'Preferences',
            child: Column(
              children: [
                AnimatedBuilder(
                  animation: AppThemeController.instance,
                  builder: (BuildContext context, _) {
                    return _ActionRow(
                      icon: Icons.dark_mode_outlined,
                      label: 'Appearance',
                      value: _themeModeLabel(
                        AppThemeController.instance.themeMode,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AppearanceSettingsPage(),
                          ),
                        );
                      },
                    );
                  },
                ),
                const Divider(height: 24),
                _ActionRow(
                  icon: Icons.security_outlined,
                  label: 'Security',
                  value: 'Session and account protection details',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SecurityPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light mode';
      case ThemeMode.dark:
        return 'Dark mode';
      case ThemeMode.system:
        return 'Follow device';
    }
  }
}

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({super.key});

  @override
  State<TransactionHistoryPage> createState() =>
      _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  bool _isLoading = false;
  String? _errorMessage;
  List<_TransactionHistoryItem> _items = const <_TransactionHistoryItem>[];
  final Map<int, String?> _listingMediaUrls = <int, String?>{};

  @override
  void initState() {
    super.initState();
    unawaited(_loadTransactions());
  }

  Future<void> _loadTransactions() async {
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      setState(() {
        _errorMessage = 'Missing account session. Please log in again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final http.Response response = await http
          .get(ApiRoutes.transactionsForUser(accountId), headers: headers)
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractTransactionError(response));
      }

      final List<_TransactionHistoryItem> parsed = _parseTransactionsResponse(
        response.body,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _items = parsed;
      });
      await _prefetchListingMedia(parsed);
    } on TimeoutException {
      _setError('Transaction request timed out.');
    } on SocketException {
      _setError('Could not connect to the transactions API.');
    } on HttpException catch (error) {
      _setError(error.message);
    } on FormatException {
      _setError('Transaction response format was invalid.');
    } catch (_) {
      _setError('Failed to load transactions.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _prefetchListingMedia(
    List<_TransactionHistoryItem> items,
  ) async {
    final List<int> listingIds = items
        .map((item) => item.listingId)
        .where((id) => id > 0 && !_listingMediaUrls.containsKey(id))
        .toSet()
        .toList(growable: false);

    if (listingIds.isEmpty) {
      return;
    }

    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      ...ApiAuthSession.authHeaders(),
    };

    for (final int listingId in listingIds) {
      try {
        final http.Response response = await http
            .get(ApiRoutes.listingMedia(listingId), headers: headers)
            .timeout(kApiRequestTimeout);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }

        final dynamic decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        final _ListingMediaResponse media = _ListingMediaResponse.fromJson(
          decoded,
        );

        final String? rawUrl = media.primaryMediaUrl ??
            (media.items.isNotEmpty ? media.items.first.fileUrl : null);
        final String? resolved = normalizeApiAssetUrl(rawUrl);
        if (!mounted) {
          return;
        }
        setState(() {
          _listingMediaUrls[listingId] = resolved;
        });
      } catch (_) {
        // Ignore media fetch failures so the list remains responsive.
      }
    }
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = message;
    });
  }

  String _extractTransactionError(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'] ?? decoded['message'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {}
    return 'Transactions request failed (HTTP ${response.statusCode}).';
  }

  List<_TransactionHistoryItem> _parseTransactionsResponse(String body) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> items = decoded is Map<String, dynamic>
        ? (decoded['items'] as List<dynamic>? ?? const <dynamic>[])
        : decoded is List
            ? decoded
            : const <dynamic>[];

    return items
        .whereType<Map<String, dynamic>>()
        .map(_TransactionHistoryItem.fromJson)
        .toList(growable: false);
  }

  String _summaryText(String username) {
    if (_items.isEmpty) {
      return 'No transactions recorded for $username yet.';
    }
    return 'Tracking the latest purchases and sales for $username.';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final String username = ApiAuthSession.username ?? 'studket_user';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text('Transaction History'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadTransactions,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Recent activity',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _summaryText(username),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            )
          else if (_items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                'No transactions yet. Completed orders will show here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._items.map(
              (_TransactionHistoryItem item) => _TransactionHistoryTile(
                item: item,
                imageUrl: _listingMediaUrls[item.listingId],
                onTap: () {
                  final int? accountId = ApiAuthSession.accountId;
                  if (accountId == null) {
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TransactionDetailsPage(
                        accountId: accountId,
                        transactionId: item.transactionId,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TransactionHistoryTile extends StatelessWidget {
  const _TransactionHistoryTile({
    required this.item,
    required this.imageUrl,
    required this.onTap,
  });

  final _TransactionHistoryItem item;
  final String? imageUrl;
  final VoidCallback onTap;

  String _formatPrice(double price) {
    return price % 1 == 0
        ? 'PHP ${price.toStringAsFixed(0)}'
        : 'PHP ${price.toStringAsFixed(2)}';
  }

  String _formatCompletedAt() {
    if (item.completedAt == null) {
      return 'Completion time unavailable';
    }
    final DateTime local = item.completedAt!.toLocal();
    final String date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final String time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date - $time';
  }

  String _listingTypeLabel() {
    if (item.isLookingFor) {
      return 'Looking For';
    }
    final String normalized = item.listingType.trim().toLowerCase();
    if (normalized == 'looking_for' || normalized == 'looking for') {
      return 'Looking For';
    }
    if (normalized.isEmpty) {
      return 'Listing';
    }
    return normalized.replaceAll('_', ' ');
  }

  String _roleLabel() {
    final String normalized = item.role.trim().toLowerCase();
    if (normalized == 'seller') {
      return 'Sold';
    }
    if (normalized == 'buyer') {
      return 'Bought';
    }
    return normalized.isEmpty ? 'Bought' : normalized;
  }

  bool _isLookingFor() {
    if (item.isLookingFor) {
      return true;
    }
    final String normalized = item.listingType.trim().toLowerCase();
    return normalized == 'looking_for' || normalized == 'looking for';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isLookingFor = _isLookingFor();
    final String title = item.listingTitle.trim().isNotEmpty
        ? item.listingTitle.trim()
        : 'Listing #${item.listingId}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: colorScheme.surfaceContainerHigh,
                    child: imageUrl != null
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            item.role == 'seller'
                                ? Icons.sell_outlined
                                : Icons.shopping_bag_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _roleLabel() == 'Sold'
                                  ? colorScheme.primaryContainer
                                  : colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _roleLabel(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _roleLabel() == 'Sold'
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSecondaryContainer,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            item.transactionStatus,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Container(
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
                            child: Text(
                              _listingTypeLabel(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isLookingFor
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCompletedAt(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatPrice(item.agreedPrice),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TransactionDetailsPage extends StatefulWidget {
  const TransactionDetailsPage({
    super.key,
    required this.accountId,
    required this.transactionId,
  });

  final int accountId;
  final int transactionId;

  @override
  State<TransactionDetailsPage> createState() => _TransactionDetailsPageState();
}

class _TransactionDetailsPageState extends State<TransactionDetailsPage> {
  bool _isLoading = false;
  String? _errorMessage;
  _TransactionDetails? _details;
  List<_ListingMediaItem> _mediaItems = const <_ListingMediaItem>[];
  String? _primaryMediaUrl;
  bool _isReviewsLoading = false;
  String? _reviewsError;
  List<_ReviewItem> _reviews = const <_ReviewItem>[];
  int _reviewRating = 5;
  final TextEditingController _reviewCommentController =
      TextEditingController();
  bool _isSubmittingReview = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final http.Response response = await http
          .get(
            ApiRoutes.transactionForUserById(
              widget.accountId,
              widget.transactionId,
            ),
            headers: headers,
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractTransactionError(response));
      }

      final _TransactionDetails parsed =
          _TransactionDetails.fromJson(jsonDecode(response.body));
      final _ListingMediaResponse media =
          await _loadListingMedia(parsed.listingId);

      if (!mounted) {
        return;
      }
      setState(() {
        _details = parsed;
        _mediaItems = media.items;
        _primaryMediaUrl = media.primaryMediaUrl;
      });
      if (!_isLookingFor(parsed.listingType) &&
          parsed.role.trim().toLowerCase() != 'seller') {
        unawaited(_loadReviews(parsed.transactionId));
      }
    } on TimeoutException {
      _setError('Transaction details request timed out.');
    } on SocketException {
      _setError('Could not connect to the transactions API.');
    } on HttpException catch (error) {
      _setError(error.message);
    } on FormatException {
      _setError('Transaction details response format was invalid.');
    } catch (_) {
      _setError('Failed to load transaction details.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _reviewCommentController.dispose();
    super.dispose();
  }

  void _setError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errorMessage = message;
    });
  }

  String _extractTransactionError(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final String? detail = _extractErrorMessage(decoded['detail']) ??
            _extractErrorMessage(decoded['message']);
        if (detail != null && detail.trim().isNotEmpty) {
          return detail.trim();
        }
      }
    } catch (_) {}
    return 'Transaction request failed (HTTP ${response.statusCode}).';
  }

  String? _extractErrorMessage(dynamic value) {
    if (value is String) {
      return value;
    }
    if (value is Map<String, dynamic>) {
      final dynamic error = value['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error;
      }
    }
    return null;
  }

  bool _isLookingFor(String raw) {
    final String normalized = raw.trim().toLowerCase();
    return normalized == 'looking_for' || normalized == 'looking for';
  }

  Future<void> _loadReviews(int transactionId) async {
    setState(() {
      _isReviewsLoading = true;
      _reviewsError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final http.Response response = await http
          .get(ApiRoutes.reviewsForTransaction(transactionId), headers: headers)
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractTransactionError(response));
      }

      final List<_ReviewItem> parsed = _parseReviewsResponse(response.body);
      if (!mounted) {
        return;
      }
      setState(() {
        _reviews = parsed;
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
          _isReviewsLoading = false;
        });
      }
    }
  }

  List<_ReviewItem> _parseReviewsResponse(String body) {
    final dynamic decoded = jsonDecode(body);
    final List<dynamic> items = decoded is List
        ? decoded
        : decoded is Map<String, dynamic>
            ? (decoded['items'] as List<dynamic>? ?? const <dynamic>[])
            : const <dynamic>[];

    return items
        .whereType<Map<String, dynamic>>()
        .map(_ReviewItem.fromJson)
        .toList(growable: false);
  }

  void _setReviewsError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _reviewsError = message;
    });
  }

  bool _canSubmitReview(_TransactionDetails details) {
    if (_isLookingFor(details.listingType)) {
      return false;
    }
    if (details.transactionStatus.trim().toLowerCase() != 'completed') {
      return false;
    }
    return _reviews.isEmpty;
  }

  Future<void> _submitReview(_TransactionDetails details) async {
    if (_isSubmittingReview) {
      return;
    }
    final int? accountId = ApiAuthSession.accountId;
    if (accountId == null) {
      _setReviewsError('Missing account session. Please log in again.');
      return;
    }

    setState(() {
      _isSubmittingReview = true;
      _reviewsError = null;
    });

    try {
      final Map<String, String> headers = <String, String>{
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...ApiAuthSession.authHeaders(),
      };

      final Map<String, dynamic> payload = <String, dynamic>{
        'transaction_id': details.transactionId,
        'reviewer_id': accountId,
        'rating': _reviewRating,
      };

      final String comment = _reviewCommentController.text.trim();
      if (comment.isNotEmpty) {
        payload['comment'] = comment;
      }

      final http.Response response = await http
          .post(
            ApiRoutes.reviewsForSeller(details.sellerAccountId),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractTransactionError(response));
      }

      if (!mounted) {
        return;
      }
      _reviewCommentController.clear();
      setState(() {
        _reviewRating = 5;
      });
      await _loadReviews(details.transactionId);
    } on TimeoutException {
      _setReviewsError('Review submission timed out.');
    } on SocketException {
      _setReviewsError('Could not connect to the reviews API.');
    } on HttpException catch (error) {
      _setReviewsError(error.message);
    } on FormatException {
      _setReviewsError('Review response format was invalid.');
    } catch (_) {
      _setReviewsError('Failed to submit review.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
        });
      }
    }
  }

  Future<_ListingMediaResponse> _loadListingMedia(int listingId) async {
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      ...ApiAuthSession.authHeaders(),
    };

    final http.Response response = await http
        .get(ApiRoutes.listingMedia(listingId), headers: headers)
        .timeout(kApiRequestTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const _ListingMediaResponse(
        listingId: 0,
        items: <_ListingMediaItem>[],
        primaryMediaUrl: null,
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      return const _ListingMediaResponse(
        listingId: 0,
        items: <_ListingMediaItem>[],
        primaryMediaUrl: null,
      );
    }

    return _ListingMediaResponse.fromJson(decoded);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(title: const Text('Transaction Details')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.28),
                ),
              ),
              child: Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            )
          else if (_details == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Text(
                'No transaction details found.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            _TransactionDetailHeader(
              details: _details!,
              imageUrls: _mediaItems
                  .map((item) => item.fileUrl)
                  .where((url) => url.trim().isNotEmpty)
                  .toList(growable: false),
              fallbackImageUrl: _primaryMediaUrl,
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _TransactionSummaryCard(details: _details!),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SellerProfileCard(details: _details!),
            ),
            const SizedBox(height: 16),
            if (_details!.role.trim().toLowerCase() != 'seller')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _TransactionReviewSection(
                  details: _details!,
                  reviews: _reviews,
                  isLoading: _isReviewsLoading,
                  errorMessage: _reviewsError,
                  canSubmit: _canSubmitReview(_details!),
                  rating: _reviewRating,
                  commentController: _reviewCommentController,
                  isSubmitting: _isSubmittingReview,
                  onRatingChanged: (value) {
                    setState(() {
                      _reviewRating = value;
                    });
                  },
                  onSubmit: () => _submitReview(_details!),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}

class _TransactionDetailHeader extends StatefulWidget {
  const _TransactionDetailHeader({
    required this.details,
    required this.imageUrls,
    required this.fallbackImageUrl,
  });

  final _TransactionDetails details;
  final List<String> imageUrls;
  final String? fallbackImageUrl;

  @override
  State<_TransactionDetailHeader> createState() =>
      _TransactionDetailHeaderState();
}

class _TransactionDetailHeaderState extends State<_TransactionDetailHeader> {
  int _currentImageIndex = 0;
  bool _isLookingFor = false;

  @override
  void initState() {
    super.initState();
    _isLookingFor = _normalizeIsLookingFor(widget.details.listingType);
  }

  bool _normalizeIsLookingFor(String raw) {
    final String normalized = raw.trim().toLowerCase();
    return normalized == 'looking_for' || normalized == 'looking for';
  }

  String _formatPrice(double price) {
    return price % 1 == 0
        ? 'PHP ${price.toStringAsFixed(0)}'
        : 'PHP ${price.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }
    final DateTime local = value.toLocal();
    final String date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final String time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date - $time';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final List<String> resolvedUrls = widget.imageUrls
        .map(normalizeApiAssetUrl)
        .whereType<String>()
        .toList(growable: false);
    final String? fallbackUrl = normalizeApiAssetUrl(widget.fallbackImageUrl);
    final List<String> allUrls = resolvedUrls.isNotEmpty
        ? resolvedUrls
        : (fallbackUrl == null ? const <String>[] : [fallbackUrl]);
    final bool hasImages = allUrls.isNotEmpty && !_isLookingFor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImages) ...[
          AspectRatio(
            aspectRatio: 1,
            child: PageView.builder(
              itemCount: allUrls.length,
              onPageChanged: (index) {
                setState(() {
                  _currentImageIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return NetworkCachedImage(
                  imageUrl: allUrls[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(allUrls.length, (index) {
              final bool isActive = index == _currentImageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: isActive ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? colorScheme.primary : Colors.grey[300],
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ],
        Padding(
          padding: EdgeInsets.fromLTRB(16, hasImages ? 16 : 24, 16, 0),
          child: Container(
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
                  widget.details.listingTitle,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Status: ${widget.details.transactionStatus}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _DetailChip(
                      label: 'Role',
                      value: widget.details.role.toUpperCase(),
                    ),
                    _DetailChip(
                      label: 'Quantity',
                      value: '${widget.details.quantity}',
                    ),
                    _DetailChip(
                      label: 'Agreed',
                      value: _formatPrice(widget.details.agreedPrice),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Completed: ${_formatDate(widget.details.completedAt)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $value',
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TransactionSummaryCard extends StatelessWidget {
  const _TransactionSummaryCard({required this.details});

  final _TransactionDetails details;

  String _formatPrice(double value) {
    return value % 1 == 0
        ? 'PHP ${value.toStringAsFixed(0)}'
        : 'PHP ${value.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) {
      return 'Not available';
    }
    final DateTime local = value.toLocal();
    final String date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final String time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return '$date • $time';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isBuyer =
        details.role.trim().toLowerCase() == 'buyer';

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
            'Transaction Summary',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Status', value: details.transactionStatus),
          _InfoRow(label: 'Role', value: isBuyer ? 'Buyer' : 'Seller'),
          _InfoRow(label: 'Quantity', value: '${details.quantity}'),
          _InfoRow(label: 'Agreed Price', value: _formatPrice(details.agreedPrice)),
          _InfoRow(label: 'Completed', value: _formatDate(details.completedAt)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
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
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerProfileCard extends StatefulWidget {
  const _SellerProfileCard({required this.details});

  final _TransactionDetails details;

  @override
  State<_SellerProfileCard> createState() => _SellerProfileCardState();
}

class _SellerProfileCardState extends State<_SellerProfileCard> {
  bool _isLoadingRating = false;
  double? _averageRating;
  int _reviewCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSellerRating();
  }

  Future<void> _loadSellerRating() async {
    final int sellerId = widget.details.sellerAccountId;
    if (sellerId <= 0 || _isLoadingRating) {
      return;
    }

    setState(() {
      _isLoadingRating = true;
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

      final List<int> ratings = _parseRatings(response.body);
      if (!mounted) {
        return;
      }
      if (ratings.isEmpty) {
        setState(() {
          _averageRating = null;
          _reviewCount = 0;
        });
        return;
      }
      final int total = ratings.fold<int>(0, (sum, value) => sum + value);
      setState(() {
        _reviewCount = ratings.length;
        _averageRating = total / ratings.length;
      });
    } catch (_) {
      // Ignore rating failures for card rendering.
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingRating = false;
        });
      }
    }
  }

  List<int> _parseRatings(String body) {
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool userIsSeller = ApiAuthSession.isSeller;
    final bool showBuyer = userIsSeller;
    final int accountId =
        showBuyer ? widget.details.buyerAccountId : widget.details.sellerAccountId;
    final String displayName =
        showBuyer ? widget.details.buyerUsername : widget.details.sellerUsername;
    final String displayEmail =
        showBuyer ? widget.details.buyerEmail : widget.details.sellerEmail;
    final String displayCampus =
        showBuyer ? widget.details.buyerCampus : widget.details.sellerCampus;
    final bool canTap = userIsSeller && accountId > 0;
    final String roleLabel = showBuyer ? 'Buyer' : 'Seller';

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: !canTap
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SellerProfilePage(
                      sellerName: displayName,
                      sellerAvatarUrl: '',
                      sellerRating: 0,
                      sellerAccountId: accountId,
                    ),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AccountAvatar(
                accountId: accountId,
                radius: 24,
                label: displayName,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (_isLoadingRating)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    else if (_reviewCount == 0)
                      Text(
                        'No ratings yet',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Row(
                        children: [
                          RatingStars(
                            rating: _averageRating ?? 0,
                            showValue: true,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '($_reviewCount)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: showBuyer
                            ? colorScheme.tertiaryContainer
                            : colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        roleLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: showBuyer
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (displayEmail.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        displayEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (displayCampus.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        displayCampus,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canTap)
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionHistoryItem {
  const _TransactionHistoryItem({
    required this.role,
    required this.transactionId,
    required this.listingId,
    required this.listingType,
    required this.listingTitle,
    required this.isLookingFor,
    required this.buyerId,
    required this.sellerId,
    required this.quantity,
    required this.agreedPrice,
    required this.transactionStatus,
    required this.completedAt,
  });

  final String role;
  final int transactionId;
  final int listingId;
  final String listingType;
  final String listingTitle;
  final bool isLookingFor;
  final int buyerId;
  final int sellerId;
  final int quantity;
  final double agreedPrice;
  final String transactionStatus;
  final DateTime? completedAt;

  factory _TransactionHistoryItem.fromJson(Map<String, dynamic> json) {
    return _TransactionHistoryItem(
      role: (json['role'] as String?)?.trim().isNotEmpty == true
          ? (json['role'] as String)
          : 'buyer',
      transactionId: (json['transaction_id'] as num?)?.toInt() ?? 0,
      listingId: (json['listing_id'] as num?)?.toInt() ?? 0,
      listingType: (json['listing_type'] as String?)?.trim() ?? '',
      listingTitle: (json['listing_title'] as String?)?.trim() ?? '',
      isLookingFor: json['is_looking_for'] == true,
      buyerId: (json['buyer_id'] as num?)?.toInt() ?? 0,
      sellerId: (json['seller_id'] as num?)?.toInt() ?? 0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      agreedPrice: (json['agreed_price'] as num?)?.toDouble() ?? 0,
      transactionStatus:
          (json['transaction_status'] as String?)?.trim().isNotEmpty == true
              ? (json['transaction_status'] as String)
              : 'unknown',
      completedAt: _parseDate(json['completed_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class _TransactionDetails {
  const _TransactionDetails({
    required this.role,
    required this.transactionId,
    required this.transactionStatus,
    required this.quantity,
    required this.agreedPrice,
    required this.completedAt,
    required this.listingId,
    required this.listingType,
    required this.listingTitle,
    required this.sellerAccountId,
    required this.buyerAccountId,
    required this.buyerUsername,
    required this.buyerEmail,
    required this.buyerCampus,
    required this.sellerUsername,
    required this.sellerEmail,
    required this.sellerCampus,
  });

  final String role;
  final int transactionId;
  final String transactionStatus;
  final int quantity;
  final double agreedPrice;
  final DateTime? completedAt;
  final int listingId;
  final String listingType;
  final String listingTitle;
  final int sellerAccountId;
  final int buyerAccountId;
  final String buyerUsername;
  final String buyerEmail;
  final String buyerCampus;
  final String sellerUsername;
  final String sellerEmail;
  final String sellerCampus;

  factory _TransactionDetails.fromJson(Map<String, dynamic> json) {
    return _TransactionDetails(
      role: (json['role'] as String?)?.trim().isNotEmpty == true
          ? (json['role'] as String)
          : 'buyer',
      transactionId: (json['transaction_id'] as num?)?.toInt() ?? 0,
      transactionStatus:
          (json['transaction_status'] as String?)?.trim().isNotEmpty == true
              ? (json['transaction_status'] as String)
              : 'unknown',
      quantity: (json['transaction_quantity'] as num?)?.toInt() ??
          (json['transactionQuantity'] as num?)?.toInt() ??
          0,
      agreedPrice: (json['transaction_agreed_price'] as num?)?.toDouble() ?? 0,
      completedAt: _TransactionHistoryItem._parseDate(
        json['transaction_completed_at'],
      ),
      listingId: (json['listing_id'] as num?)?.toInt() ??
          (json['transaction_listing_id'] as num?)?.toInt() ??
          0,
      listingType: (json['listing_type'] as String?)?.trim() ?? '',
      listingTitle: (json['listing_title'] as String?)?.trim().isNotEmpty == true
          ? (json['listing_title'] as String)
          : 'Listing',
      sellerAccountId: (json['seller_account_id'] as num?)?.toInt() ??
          (json['listing_seller_id'] as num?)?.toInt() ??
          (json['seller_id'] as num?)?.toInt() ??
          0,
      buyerAccountId: (json['buyer_account_id'] as num?)?.toInt() ??
          (json['buyer_id'] as num?)?.toInt() ??
          0,
      buyerUsername: (json['buyer_username'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['buyer_username'] as String)
          : 'Buyer',
      buyerEmail: (json['buyer_email'] as String?)?.trim().isNotEmpty == true
          ? (json['buyer_email'] as String)
          : '-',
      buyerCampus: (json['buyer_campus'] as String?)?.trim().isNotEmpty == true
          ? (json['buyer_campus'] as String)
          : '-',
      sellerUsername: (json['seller_username'] as String?)?.trim().isNotEmpty ==
              true
          ? (json['seller_username'] as String)
          : 'Seller',
      sellerEmail: (json['seller_email'] as String?)?.trim().isNotEmpty == true
          ? (json['seller_email'] as String)
          : '-',
      sellerCampus: (json['seller_campus'] as String?)?.trim().isNotEmpty == true
          ? (json['seller_campus'] as String)
          : '-',
    );
  }
}

class _TransactionReviewSection extends StatelessWidget {
  const _TransactionReviewSection({
    required this.details,
    required this.reviews,
    required this.isLoading,
    required this.errorMessage,
    required this.canSubmit,
    required this.rating,
    required this.commentController,
    required this.isSubmitting,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  final _TransactionDetails details;
  final List<_ReviewItem> reviews;
  final bool isLoading;
  final String? errorMessage;
  final bool canSubmit;
  final int rating;
  final TextEditingController commentController;
  final bool isSubmitting;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  bool _isLookingFor() {
    final String normalized = details.listingType.trim().toLowerCase();
    return normalized == 'looking_for' || normalized == 'looking for';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isLookingFor = _isLookingFor();

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
            'Reviews',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          if (isLookingFor)
            Text(
              'Reviews are not supported for looking-for transactions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (errorMessage != null)
            Text(
              errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            )
          else if (reviews.isNotEmpty)
            Column(
              children: reviews
                  .map(
                    (_ReviewItem review) => _ReviewTile(review: review),
                  )
                  .toList(growable: false),
            )
          else if (!canSubmit)
            Text(
              'No reviews available yet.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          else ...[
            _ReviewRatingPicker(
              rating: rating,
              onChanged: onRatingChanged,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
              ),
            ),
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
          ],
        ],
      ),
    );
  }
}

class _ReviewRatingPicker extends StatelessWidget {
  const _ReviewRatingPicker({
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

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final _ReviewItem review;

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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(5, (index) {
              final bool isActive = index < review.rating;
              return Icon(
                isActive ? Icons.star_rounded : Icons.star_border_rounded,
                size: 18,
                color: isActive ? colorScheme.primary : colorScheme.outline,
              );
            }),
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.comment,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
          ],
          if (review.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              _formatDate(review.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewItem {
  const _ReviewItem({
    required this.reviewId,
    required this.transactionId,
    required this.reviewerId,
    required this.revieweeId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  final int reviewId;
  final int transactionId;
  final int reviewerId;
  final int revieweeId;
  final int rating;
  final String comment;
  final DateTime? createdAt;

  factory _ReviewItem.fromJson(Map<String, dynamic> json) {
    return _ReviewItem(
      reviewId: (json['review_id'] as num?)?.toInt() ?? 0,
      transactionId: (json['transaction_id'] as num?)?.toInt() ?? 0,
      reviewerId: (json['reviewer_id'] as num?)?.toInt() ?? 0,
      revieweeId: (json['reviewee_id'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: (json['comment'] as String?)?.trim() ?? '',
      createdAt: _TransactionHistoryItem._parseDate(json['created_at']),
    );
  }
}

class _ListingMediaResponse {
  const _ListingMediaResponse({
    required this.listingId,
    required this.items,
    required this.primaryMediaUrl,
  });

  final int listingId;
  final List<_ListingMediaItem> items;
  final String? primaryMediaUrl;

  factory _ListingMediaResponse.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawItems =
        (json['items'] as List<dynamic>? ?? const <dynamic>[]);
    return _ListingMediaResponse(
      listingId: (json['listing_id'] as num?)?.toInt() ?? 0,
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(_ListingMediaItem.fromJson)
          .toList(growable: false),
      primaryMediaUrl: (json['primary_media_url'] as String?)?.trim(),
    );
  }
}

class _ListingMediaItem {
  const _ListingMediaItem({
    required this.mediaId,
    required this.listingId,
    required this.filePath,
    required this.fileUrl,
    required this.sortOrder,
  });

  final int mediaId;
  final int listingId;
  final String filePath;
  final String fileUrl;
  final int sortOrder;

  factory _ListingMediaItem.fromJson(Map<String, dynamic> json) {
    return _ListingMediaItem(
      mediaId: (json['media_id'] as num?)?.toInt() ?? 0,
      listingId: (json['listing_id'] as num?)?.toInt() ?? 0,
      filePath: (json['file_path'] as String?)?.trim() ?? '',
      fileUrl: (json['file_url'] as String?)?.trim() ?? '',
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class DebugSettingsPage extends StatefulWidget {
  const DebugSettingsPage({super.key});

  @override
  State<DebugSettingsPage> createState() => _DebugSettingsPageState();
}

class _DebugSettingsPageState extends State<DebugSettingsPage> {
  String? _debugApiBaseUrlOverride = getDebugApiBaseUrlOverride();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Debug Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiscordSectionCard(
            title: 'Networking',
            child: Column(
              children: [
                _ActionRow(
                  icon: Icons.api_outlined,
                  label: 'API Base URL',
                  value: _debugApiBaseUrlOverride ?? 'Using build default',
                  onTap: _editDebugApiBaseUrlOverride,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDebugApiBaseUrlOverride() async {
    final _DebugApiBaseUrlDialogResult? result =
        await showDialog<_DebugApiBaseUrlDialogResult>(
          context: context,
          builder: (BuildContext context) {
            return _DebugApiBaseUrlDialog(
              initialValue: _debugApiBaseUrlOverride,
            );
          },
        );

    if (result == null) {
      return;
    }

    try {
      if (result.action == _DebugApiBaseUrlAction.reset) {
        await setDebugApiBaseUrlOverride(null);
      } else {
        await setDebugApiBaseUrlOverride(result.value);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _debugApiBaseUrlOverride = getDebugApiBaseUrlOverride();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _debugApiBaseUrlOverride == null
                ? 'Using build default API URL.'
                : 'Debug API URL updated.',
          ),
        ),
      );
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

enum _DebugApiBaseUrlAction { save, reset }

class _DebugApiBaseUrlDialogResult {
  const _DebugApiBaseUrlDialogResult({required this.action, this.value});

  final _DebugApiBaseUrlAction action;
  final String? value;
}

class _DebugApiBaseUrlDialog extends StatefulWidget {
  const _DebugApiBaseUrlDialog({required this.initialValue});

  final String? initialValue;

  @override
  State<_DebugApiBaseUrlDialog> createState() => _DebugApiBaseUrlDialogState();
}

class _DebugApiBaseUrlDialogState extends State<_DebugApiBaseUrlDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Debug API base URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'https://example.ngrok-free.dev/api/v1',
              labelText: 'Base URL',
              errorText: _errorText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Leave blank to use the build default. If you enter only an origin, /api/v1 is added automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(
              const _DebugApiBaseUrlDialogResult(
                action: _DebugApiBaseUrlAction.reset,
              ),
            );
          },
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _save() {
    final String value = _controller.text.trim();
    if (value.isEmpty) {
      Navigator.of(context).pop(
        const _DebugApiBaseUrlDialogResult(
          action: _DebugApiBaseUrlAction.reset,
        ),
      );
      return;
    }

    final Uri? parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.hasScheme ||
        parsed.host.trim().isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      setState(() {
        _errorText = 'Enter a full http:// or https:// URL.';
      });
      return;
    }

    Navigator.of(context).pop(
      _DebugApiBaseUrlDialogResult(
        action: _DebugApiBaseUrlAction.save,
        value: value,
      ),
    );
  }
}

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(title: const Text('Security')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DiscordSectionCard(
            title: 'Session',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _SettingInfoLine(
                  label: 'Saved Session',
                  value: 'Active on this device',
                ),
                _SettingInfoLine(
                  label: 'Realtime Connection',
                  value: 'Disconnected when logging out',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DiscordSectionCard(
            title: 'Security Notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Use logout if you are sharing this device or want to clear the locally saved session.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Password change and session management endpoints are not documented in the current backend reference yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
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

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppThemeController.instance,
      builder: (BuildContext context, _) {
        final ThemeMode selectedMode = AppThemeController.instance.themeMode;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(title: const Text('Appearance')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DiscordSectionCard(
                title: 'Theme',
                child: RadioGroup<ThemeMode?>(
                  groupValue: selectedMode,
                  onChanged: (ThemeMode? nextValue) {
                    if (nextValue == null) {
                      return;
                    }
                    AppThemeController.instance.setThemeMode(nextValue);
                  },
                  child: Column(
                    children: [
                      _ThemeModeTile(
                        title: 'Follow Device',
                        subtitle: 'Use the system light or dark preference.',
                        value: ThemeMode.system,
                      ),
                      const Divider(height: 24),
                      _ThemeModeTile(
                        title: 'Light',
                        subtitle: 'Always use the light theme.',
                        value: ThemeMode.light,
                      ),
                      const Divider(height: 24),
                      _ThemeModeTile(
                        title: 'Dark',
                        subtitle: 'Always use the dark theme.',
                        value: ThemeMode.dark,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final String title;
  final String subtitle;
  final ThemeMode value;

  @override
  Widget build(BuildContext context) {
    return RadioListTile<ThemeMode?>(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle),
      value: value,
    );
  }
}

class _SettingInfoLine extends StatelessWidget {
  const _SettingInfoLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
