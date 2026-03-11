import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_notifications.dart';
import 'app_entry_page.dart';
import 'api/api_auth_session.dart';
import 'api/api_base_url.dart';
import 'api/api_routes.dart';
import 'api/tags_api.dart';
import 'api/user_realtime_service.dart';
import 'chats_page.dart';
import 'components/studket_app_bar.dart';
import 'notifications_page.dart';
import 'user_profile_page.dart';
import 'listing_editor_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppNotifications.instance.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studket',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const AppEntryPage(),
    );
  }
}

class FeedListing {
  const FeedListing({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    required this.campus,
    required this.tags,
    required this.listingType,
    required this.status,
    required this.sellerUsername,
    required this.sellerAverageRating,
    required this.sellerReviewCount,
    required this.sellerIsTrusted,
  });

  final int id;
  final String title;
  final String description;
  final num? price;
  final String campus;
  final List<String> tags;
  final String listingType;
  final String status;
  final String sellerUsername;
  final num? sellerAverageRating;
  final int sellerReviewCount;
  final bool sellerIsTrusted;

  factory FeedListing.fromJson(Map<String, dynamic> json) {
    return FeedListing(
      id: (json['listing_id'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? 'Untitled Listing').toString(),
      description: (json['description'] ?? '').toString(),
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
      sellerAverageRating: json['seller_average_rating'] as num?,
      sellerReviewCount: (json['seller_review_count'] as num?)?.toInt() ?? 0,
      sellerIsTrusted:
          json['seller_is_trusted'] == true || json['seller_is_verified'] == true,
    );
  }
}

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

  String _formatPrice(num? value) {
    if (value == null) {
      return 'Price unavailable';
    }
    final String amount = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return 'PHP $amount';
  }

  int get _notificationBadgeCount => _realtime.notifications
      .where((UserRealtimeNotification item) => !item.isRead)
      .length;

  int get _chatBadgeCount => _realtime.newMessageConversationCount;

  bool get _showSellerPostButton =>
      currentPageIndex == 0 && ApiAuthSession.isSeller;

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
                  'Posting is available only for seller accounts.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
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
                    final bool? created = await Navigator.of(this.context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const ListingEditorPage(),
                      ),
                    );
                    if (created == true) {
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
                    'Post a buyer demand request under your seller account.',
                  ),
                  onTap: () async {
                    Navigator.of(context).pop();
                    final bool? created = await Navigator.of(this.context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => const ListingEditorPage(
                          listingType: 'looking_for',
                        ),
                      ),
                    );
                    if (created == true) {
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
                                      fillColor: Colors.white,
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
                                              selected: _selectedTags.contains(
                                                tag,
                                              ),
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
                                                color: Colors.grey[700],
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
                                      color: Colors.amber[50],
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
                                    ..._visibleSaleFeedItems.map(
                                      (FeedListing item) => _buildListingCard(
                                        context,
                                        item,
                                      ),
                                    ),
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
                                      color: Colors.amber[50],
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
                                      (FeedListing item) => _buildListingCard(
                                        context,
                                        item,
                                      ),
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
                        _formatPrice(item.price),
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
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
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
