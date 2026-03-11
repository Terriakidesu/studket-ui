import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'app_entry_page.dart';
import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/profile_picture_api.dart';
import 'api/api_routes.dart';
import 'api/api_session_storage.dart';
import 'api/auth_api.dart';
import 'api/user_realtime_service.dart';
import 'components/account_avatar.dart';

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
            statusBarColor: const Color(0xFF5865F2),
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

      if (kDebugMode) {
        debugPrint(
          'UserProfilePage._loadMyPosts -> GET ${ApiRoutes.listingsForUser(accountId)}',
        );
        debugPrint(
          'UserProfilePage._loadMyPosts -> GET ${ApiRoutes.lookingForListingsForUser(accountId)}',
        );
      }

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

      if (kDebugMode) {
        debugPrint(
          'UserProfilePage._loadMyPosts <- listings HTTP ${listingsResponse.statusCode}',
        );
        debugPrint(
          'UserProfilePage._loadMyPosts <- looking-for HTTP ${lookingForResponse.statusCode}',
        );
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

    if (kDebugMode) {
      debugPrint(
        'UserProfilePage._parseProfileListingsResponse[$label] parsed ${items.length} raw item(s)',
      );
    }

    final List<_ProfileListing> parsed = items
        .whereType<Map<String, dynamic>>()
        .map(_ProfileListing.fromJson)
        .where((item) => item.ownerId == null || item.ownerId == accountId)
        .toList(growable: false);

    if (kDebugMode) {
      debugPrint(
        'UserProfilePage._parseProfileListingsResponse[$label] kept ${parsed.length} item(s)',
      );
    }

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
      backgroundColor: const Color(0xFFF2F3F5),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 18,
                    offset: Offset(0, 8),
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
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E1F22),
                            width: 4,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 12,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            AccountAvatar(
                              accountId: ApiAuthSession.accountId,
                              radius: 42,
                              backgroundColor: const Color(0xFF1E1F22),
                              label: username,
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Material(
                                color: const Color(0xFF5865F2),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _isUploadingProfilePicture
                                      ? null
                                      : _showProfilePictureActions,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: _isUploadingProfilePicture
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.camera_alt_outlined,
                                            size: 14,
                                            color: Colors.white,
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
                      color: const Color(0xFF1E1F22),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DiscordTag(
                        label: _capitalize(accountType),
                        backgroundColor: const Color(0xFFE8EAFF),
                        foregroundColor: const Color(0xFF4752C4),
                      ),
                      _DiscordTag(
                        label: _capitalize(marketplaceRole),
                        backgroundColor: isSeller
                            ? const Color(0xFFE7F7EC)
                            : const Color(0xFFF3F4F6),
                        foregroundColor: isSeller
                            ? const Color(0xFF1F8F4D)
                            : const Color(0xFF6B7280),
                      ),
                      _DiscordTag(
                        label: isTrustedSeller
                            ? 'Trusted Seller'
                            : 'Not Trusted Yet',
                        backgroundColor: isTrustedSeller
                            ? const Color(0xFFFFF1D6)
                            : const Color(0xFFF3F4F6),
                        foregroundColor: isTrustedSeller
                            ? const Color(0xFFC27C0E)
                            : const Color(0xFF6B7280),
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
                            ? const Color(0xFFFFF6E5)
                            : const Color(0xFFEFF6FF),
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
                                ? const Color(0xFFC27C0E)
                                : const Color(0xFF2563EB),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isTrustedSeller
                                  ? 'Your account already has trusted seller status.'
                                  : 'You are already a seller. You can now request trusted seller review.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF374151),
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
                          backgroundColor: const Color(0xFF5865F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _isSubmittingTrustedSellerRequest
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
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
                              color: const Color(0xFF6B7280),
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
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: Text(
                          _myPostsError!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF991B1B),
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
                              ),
                            ),
                          );
                        },
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
                              ),
                            ),
                          );
                        },
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
}

class _ProfileListing {
  const _ProfileListing({
    required this.id,
    required this.title,
    required this.description,
    required this.listingType,
    required this.status,
    required this.price,
    required this.ownerId,
    required this.tags,
  });

  final int id;
  final String title;
  final String description;
  final String listingType;
  final String status;
  final num? price;
  final int? ownerId;
  final List<String> tags;

  factory _ProfileListing.fromJson(Map<String, dynamic> json) {
    return _ProfileListing(
      id: (json['listing_id'] as num?)?.toInt() ??
          (json['id'] as num?)?.toInt() ??
          0,
      title: (json['title'] ?? 'Untitled Listing').toString(),
      description: (json['description'] ?? '').toString(),
      listingType: (json['listing_type'] ?? 'listing').toString(),
      status: (json['status'] ?? 'unknown').toString(),
      price: json['price'] as num?,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 6),
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
              color: const Color(0xFF6B7280),
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
    final Color color = danger ? const Color(0xFFDC2626) : const Color(0xFF111827);
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
                color: danger ? const Color(0xFFFEE2E2) : const Color(0xFFF3F4F6),
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
                      color: const Color(0xFF6B7280),
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
  });

  final String title;
  final String emptyLabel;
  final List<_ProfileListing> items;
  final VoidCallback onTap;

  static const int _previewCount = 3;

  String _formatPrice(num? price) {
    if (price == null) {
      return 'Price unavailable';
    }
    return price % 1 == 0 ? 'PHP ${price.toStringAsFixed(0)}' : 'PHP ${price.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
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
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                if (items.isNotEmpty)
                  Text(
                    hasMoreThanPreview
                        ? 'Recent ${visibleItems.length} of ${items.length}'
                        : '${items.length} item${items.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (items.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF6B7280),
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
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              emptyLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7280),
              ),
            ),
          )
        else ...[
          ...visibleItems.map(
            (_ProfileListing item) => _ProfileListingCard(item: item),
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
  });

  final String title;
  final String emptyLabel;
  final List<_ProfileListing> items;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                emptyLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
              ),
            )
          else
            ...items.map(
              (_ProfileListing item) => _ProfileListingCard(item: item),
            ),
        ],
      ),
    );
  }
}

class _ProfileListingCard extends StatelessWidget {
  const _ProfileListingCard({required this.item});

  final _ProfileListing item;

  String _formatPrice(num? price) {
    if (price == null) {
      return 'Price unavailable';
    }
    return price % 1 == 0
        ? 'PHP ${price.toStringAsFixed(0)}'
        : 'PHP ${price.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
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
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _DiscordTag(
                label: item.status,
                backgroundColor: const Color(0xFFE5E7EB),
                foregroundColor: const Color(0xFF374151),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatPrice(item.price),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF2563EB),
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
                color: const Color(0xFF4B5563),
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
                      backgroundColor: const Color(0xFFE8EAFF),
                      foregroundColor: const Color(0xFF4752C4),
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
      backgroundColor: const Color(0xFFF2F3F5),
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
            child: _ActionRow(
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
          ),
        ],
      ),
    );
  }
}

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F5),
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
                    color: const Color(0xFF4B5563),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Password change and session management endpoints are not documented in the current backend reference yet.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
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
              color: const Color(0xFF9CA3AF),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
