import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/tags_api.dart';
import 'api/user_realtime_service.dart';
import 'chats_page.dart';
import 'components/studket_app_bar.dart';
import 'listing_editor_page.dart';
import 'models/feed_listing.dart';
import 'network_cached_image.dart';
import 'notifications_page.dart';
import 'product_details_page.dart';
import 'user_profile_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentPageIndex = 0;
  final UserRealtimeService _realtime = UserRealtimeService.instance;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedTags = <String>{};

  static const List<String> _fallbackFeedTags = <String>[
    'food',
    'beverages',
    'school_supplies',
    'books',
    'academic_materials',
    'gadgets',
    'electronics',
    'clothing',
    'second_hand_items',
    'looking_for',
  ];

  bool _isLoadingFeed = false;
  List<String> _feedTags = _fallbackFeedTags;
  String? _feedError;
  List<FeedListing> _feedItems = const <FeedListing>[];

  @override
  void initState() {
    super.initState();
    unawaited(_realtime.ensureConnected());
    unawaited(_refreshFeedView());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchFeed() async {
    setState(() {
      _isLoadingFeed = true;
      _feedError = null;
    });

    try {
      final Uri uri = ApiRoutes.listingsFeed(
        userId: ApiAuthSession.accountId,
        tags: _selectedTags.toList(growable: false),
        limit: 50,
      );
      final http.Response response = await http
          .get(
            uri,
            headers: <String, String>{
              'Accept': 'application/json',
              ...ApiAuthSession.authHeaders(),
            },
          )
          .timeout(kApiRequestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(_extractFeedError(response));
      }

      final dynamic decoded = jsonDecode(response.body);
      final List<dynamic> items = decoded is Map<String, dynamic>
          ? (decoded['items'] as List<dynamic>? ?? const <dynamic>[])
          : const <dynamic>[];

      final List<FeedListing> parsed = items
          .whereType<Map<String, dynamic>>()
          .map(FeedListing.fromJson)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _feedItems = parsed;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _feedError = 'Feed request timed out.';
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _feedError = 'Could not connect to the listings feed.';
      });
    } on HttpException catch (error) {
      if (!mounted) return;
      setState(() {
        _feedError = error.message;
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _feedError = 'Feed response format was invalid.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _feedError = 'Failed to load feed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingFeed = false;
        });
      }
    }
  }

  Future<void> _refreshFeedView() async {
    await _loadPopularTags();
    await _fetchFeed();
  }

  Future<void> _loadPopularTags() async {
    try {
      final List<String> tags = await TagsApi.fetchPopularTags();
      if (tags.isEmpty || !mounted) {
        return;
      }
      setState(() {
        _feedTags = tags;
        _selectedTags.removeWhere((String tag) => !_feedTags.contains(tag));
      });
    } catch (_) {}
  }

  String _extractFeedError(http.Response response) {
    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final dynamic detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }
        if (detail is Map<String, dynamic>) {
          final dynamic error = detail['error'];
          if (error is String && error.trim().isNotEmpty) {
            return error.trim();
          }
        }
      }
    } catch (_) {}
    return 'Feed request failed (HTTP ${response.statusCode}).';
  }

  List<FeedListing> get _visibleFeedItems {
    final String query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return _feedItems;
    }

    return _feedItems.where((FeedListing item) {
      return item.title.toLowerCase().contains(query) ||
          item.description.toLowerCase().contains(query) ||
          item.campus.toLowerCase().contains(query) ||
          item.sellerUsername.toLowerCase().contains(query) ||
          item.tags.any((String tag) => tag.toLowerCase().contains(query));
    }).toList(growable: false);
  }

  List<FeedListing> get _visibleSaleFeedItems {
    return _visibleFeedItems
        .where((FeedListing item) => item.listingType != 'looking_for')
        .toList(growable: false);
  }

  List<FeedListing> get _visibleLookingForItems {
    return _visibleFeedItems
        .where((FeedListing item) => item.listingType == 'looking_for')
        .toList(growable: false);
  }

  void _toggleTag(String tag, bool selected) {
    setState(() {
      if (selected) {
        _selectedTags.add(tag);
      } else {
        _selectedTags.remove(tag);
      }
    });
    unawaited(_fetchFeed());
  }

  String _formatMoney(num? value) {
    if (value == null) {
      return 'Price unavailable';
    }
    final String amount = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return 'PHP $amount';
  }

  String _formatListingAmount(FeedListing item) {
    if (item.listingType == 'looking_for') {
      if (item.budgetMin != null && item.budgetMax != null) {
        return '${_formatMoney(item.budgetMin)} - ${_formatMoney(item.budgetMax)}';
      }
      return _formatMoney(item.budgetMin ?? item.price);
    }
    return _formatMoney(item.price);
  }

  int get _notificationBadgeCount => _realtime.notifications
      .where((UserRealtimeNotification item) => !item.isRead)
      .length;

  int get _chatBadgeCount => _realtime.newMessageConversationCount;

  bool get _showSellerPostButton =>
      currentPageIndex == 0 && ApiAuthSession.accountId != null;

  Future<void> _showSellerPostActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Post',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  ApiAuthSession.isSeller
                      ? 'Create either a sale listing or a looking for post.'
                      : 'You can create a looking for post now. Sale listings require seller access.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                if (ApiAuthSession.isSeller)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.sell_outlined),
                    ),
                    title: const Text('Create Listing'),
                    subtitle: const Text(
                      'Post an item for sale as a seller account.',
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final ListingEditorResult? created =
                          await Navigator.of(this.context)
                              .push<ListingEditorResult>(
                        MaterialPageRoute(
                          builder: (_) => const ListingEditorPage(),
                        ),
                      );
                      if (created == ListingEditorResult.updated) {
                        await _fetchFeed();
                        if (!mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Listing posted.')),
                        );
                      }
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    child: Icon(Icons.search_outlined),
                  ),
                  title: const Text('Create Looking For Post'),
                  subtitle: const Text(
                    'Post a buyer demand request for something you need.',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final ListingEditorResult? created =
                        await Navigator.of(this.context)
                            .push<ListingEditorResult>(
                      MaterialPageRoute(
                        builder: (_) => const ListingEditorPage(
                          listingType: 'looking_for',
                        ),
                      ),
                    );
                    if (created == ListingEditorResult.updated) {
                      await _fetchFeed();
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Looking for post created.'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StudketAppBar(
        title: widget.title,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        titleSpacing: 20,
        titleStyle: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        actions: [
          AnimatedBuilder(
            animation: _realtime,
            builder: (BuildContext context, _) {
              return _BadgedAppBarAction(
                tooltip: 'Notifications',
                icon: Icons.notifications_none,
                count: _notificationBadgeCount,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationsPage(),
                    ),
                  );
                },
              );
            },
          ),
          AnimatedBuilder(
            animation: _realtime,
            builder: (BuildContext context, _) {
              return _BadgedAppBarAction(
                tooltip: 'Chats',
                icon: Icons.chat_bubble_outline,
                count: _chatBadgeCount,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ChatsPage()),
                  );
                },
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Theme.of(context).colorScheme.onPrimary.withValues(
                  alpha: 0.18,
                ),
          ),
        ),
      ),
      body: Center(
        child: currentPageIndex == 0
            ? DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    Material(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: TabBar(
                        labelColor: Theme.of(context).colorScheme.primary,
                        tabs: const [
                          Tab(text: 'Feed'),
                          Tab(text: 'Looking For'),
                        ],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: RefreshIndicator(
                              onRefresh: _refreshFeedView,
                              child: ListView(
                                children: [
                                  TextField(
                                    controller: _searchController,
                                    textInputAction: TextInputAction.search,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      hintText: 'Search loaded listings',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.close),
                                      ),
                                      filled: true,
                                      fillColor: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerLowest,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        borderSide: BorderSide.none,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    height: 40,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _feedTags.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 8),
                                      itemBuilder:
                                          (BuildContext context, int index) {
                                        final String tag = _feedTags[index];
                                        return FilterChip(
                                          label: Text(tag),
                                          selected: _selectedTags.contains(tag),
                                          onSelected: (bool selected) {
                                            _toggleTag(tag, selected);
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedTags.isEmpty
                                              ? 'Showing all feed tags'
                                              : 'Filtering by: ${_selectedTags.join(', ')}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      FilledButton.tonal(
                                        onPressed: _isLoadingFeed
                                            ? null
                                            : _refreshFeedView,
                                        child: const Text('Reload'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (_isLoadingFeed)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 80),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else if (_feedError != null)
                                    Card(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Feed Error',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(_feedError!),
                                          ],
                                        ),
                                      ),
                                    )
                                  else if (_visibleFeedItems.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 80),
                                      child: Center(
                                        child: Text(
                                          'No feed items matched the current search or tag filters.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  else
                                    _buildSaleListingGrid(context),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: RefreshIndicator(
                              onRefresh: _refreshFeedView,
                              child: ListView(
                                children: [
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Looking For',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _selectedTags.isEmpty
                                                ? 'Wanted-item posts from the live listings feed.'
                                                : 'Filtered by: ${_selectedTags.join(', ')}',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  if (_isLoadingFeed)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 80),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    )
                                  else if (_feedError != null)
                                    Card(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .errorContainer,
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: Text(_feedError!),
                                      ),
                                    )
                                  else if (_visibleLookingForItems.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 80),
                                      child: Center(
                                        child: Text(
                                          'No looking for posts matched the current search or tag filters.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  else
                                    ..._visibleLookingForItems.map(
                                      (FeedListing item) =>
                                          _buildListingCard(context, item),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            : const UserProfilePage(),
      ),
      floatingActionButton: _showSellerPostButton
          ? FloatingActionButton(
              onPressed: _showSellerPostActions,
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: currentPageIndex,
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(BuildContext context, FeedListing item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProductDetailsPage(
                listingId: item.id,
                listingType: item.listingType,
                shareToken: item.shareToken,
                shareUrl: item.shareUrl,
                productName: item.title,
                productPrice: _formatListingAmount(item),
                productLocation: item.campus,
                productDescription: item.description.isEmpty
                    ? 'No description provided.'
                    : item.description,
                imageUrls: item.imageUrls,
                sellerName: item.sellerUsername,
                sellerAccountId: item.ownerId,
                sellerAvatarUrl: item.sellerAvatarUrl ?? '',
                sellerRating: item.sellerAverageRating?.toDouble() ?? 0,
              ),
            ),
          );
        },
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
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatListingAmount(item),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
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
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.description.isEmpty
                    ? 'No description provided.'
                    : item.description,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(icon: Icons.storefront, label: item.sellerUsername),
                  _MetaPill(
                    icon: Icons.location_on_outlined,
                    label: item.campus,
                  ),
                  _MetaPill(
                    icon: Icons.category_outlined,
                    label: item.listingType,
                  ),
                  if (item.sellerAverageRating != null)
                    _MetaPill(
                      icon: Icons.star_outline,
                      label:
                          '${item.sellerAverageRating} (${item.sellerReviewCount})',
                    ),
                  if (item.sellerIsTrusted)
                    const _MetaPill(
                      icon: Icons.verified,
                      label: 'Trusted seller',
                    ),
                ],
              ),
              if (item.tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: item.tags
                      .map(
                        (String tag) => Chip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaleListingGrid(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: _visibleSaleFeedItems.length,
      itemBuilder: (BuildContext context, int index) {
        final FeedListing item = _visibleSaleFeedItems[index];
        return _SaleFeedCard(
          title: item.title,
          priceLabel: _formatListingAmount(item),
          campus: item.campus,
          status: item.status,
          sellerName: item.sellerUsername,
          imageUrl: item.imageUrls.isEmpty ? null : item.imageUrls.first,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ProductDetailsPage(
                  listingId: item.id,
                  listingType: item.listingType,
                  shareToken: item.shareToken,
                  shareUrl: item.shareUrl,
                  productName: item.title,
                  productPrice: _formatListingAmount(item),
                  productLocation: item.campus,
                  productDescription: item.description.isEmpty
                      ? 'No description provided.'
                      : item.description,
                  imageUrls: item.imageUrls,
                  sellerName: item.sellerUsername,
                  sellerAccountId: item.ownerId,
                  sellerAvatarUrl: item.sellerAvatarUrl ?? '',
                  sellerRating: item.sellerAverageRating?.toDouble() ?? 0,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SaleFeedCard extends StatelessWidget {
  const _SaleFeedCard({
    required this.title,
    required this.priceLabel,
    required this.campus,
    required this.status,
    required this.sellerName,
    required this.imageUrl,
    required this.onTap,
  });

  final String title;
  final String priceLabel;
  final String campus;
  final String status;
  final String sellerName;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null)
                    NetworkCachedImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                  else
                    Container(
                      color: colorScheme.surfaceContainerHigh,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.image_outlined,
                        size: 36,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        status,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 5,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double height = constraints.maxHeight;
                  final double padding = height < 88 ? 10 : 12;
                  final double gap = height < 88 ? 3 : 4;
                  final double iconSize = height < 88 ? 14 : 16;
                  final int titleMaxLines = height < 88 ? 1 : 2;

                  return Padding(
                    padding: EdgeInsets.all(padding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          priceLabel,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: gap),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                            maxLines: titleMaxLines,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(height: gap),
                        _CardMetaRow(
                          icon: Icons.location_on_outlined,
                          label: campus,
                          iconSize: iconSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: gap),
                        _CardMetaRow(
                          icon: Icons.storefront_outlined,
                          label: sellerName,
                          iconSize: iconSize,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardMetaRow extends StatelessWidget {
  const _CardMetaRow({
    required this.icon,
    required this.label,
    required this.iconSize,
    required this.color,
  });

  final IconData icon;
  final String label;
  final double iconSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: iconSize, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _BadgedAppBarAction extends StatelessWidget {
  const _BadgedAppBarAction({
    required this.tooltip,
    required this.icon,
    required this.count,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = Theme.of(context).colorScheme.error;
    final Color badgeForeground = Theme.of(context).colorScheme.onError;
    final String label = count > 99 ? '99+' : '$count';

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
          ),
          if (count > 0)
            Positioned(
              right: 4,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 1,
                ),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: badgeForeground,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
