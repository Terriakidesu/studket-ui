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
import 'listing_editor_page.dart';

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

  @override
  void initState() {
    super.initState();
    if (ApiAuthSession.isSeller) {
      unawaited(_loadMyPosts());
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

  static const int _previewCount = 3;

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
        padding: const EdgeInsets.all(16),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                ),
              ),
              const SizedBox(width: 8),
                       _DiscordTag(
                         label: item.status,
                         backgroundColor: colorScheme.surfaceContainerHighest,
                         foregroundColor: colorScheme.onSurfaceVariant,
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
          const SizedBox(height: 6),
          Text(
            _formatListingAmount(item),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (item.description.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              item.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: item.tags
                  .map(
                    (String tag) => _DiscordTag(
                      label: tag,
                      backgroundColor: colorScheme.secondaryContainer,
                      foregroundColor: colorScheme.onSecondaryContainer,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
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
