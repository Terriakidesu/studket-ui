import 'package:flutter/material.dart';

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
  @override
  Widget build(BuildContext context) {
    final bool hasSellerAvatar = widget.sellerAvatarUrl.trim().isNotEmpty;
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
                    backgroundImage: hasSellerAvatar
                        ? NetworkImage(widget.sellerAvatarUrl)
                        : null,
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
                          rating: widget.sellerRating,
                          showValue: true,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Product and review endpoints remain local because the backend reference only exposes public auth routes for user accounts.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[700]),
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
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No public seller listing endpoint is available for normal user accounts.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        'No public review endpoint is available for normal user accounts.',
                        textAlign: TextAlign.center,
                      ),
                    ),
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
