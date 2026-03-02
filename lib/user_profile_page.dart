import 'package:flutter/material.dart';
import 'components/product_grid_card.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

enum _ProfileMode { seller, buyer }

class _UserProfilePageState extends State<UserProfilePage> {
  _ProfileMode _mode = _ProfileMode.buyer;
  bool _isSellerAccount = false;

  static const List<Map<String, String>> _myListings = [
    {
      'name': 'Minimal Backpack',
      'location': 'Seattle, WA',
      'image': 'https://picsum.photos/seed/my_backpack/300',
    },
    {
      'name': 'Ceramic Coffee Mug',
      'location': 'Chicago, IL',
      'image': 'https://picsum.photos/seed/my_mug/300',
    },
    {
      'name': 'Laptop Stand',
      'location': 'New York, NY',
      'image': 'https://picsum.photos/seed/my_stand/300',
    },
    {
      'name': 'Running Shoes',
      'location': 'Portland, OR',
      'image': 'https://picsum.photos/seed/my_shoes/300',
    },
  ];

  static const List<Map<String, String>> _recentPurchases = [
    {
      'name': 'Smart Watch',
      'location': 'Boston, MA',
      'image': 'https://picsum.photos/seed/buy_watch/300',
    },
    {
      'name': 'Wooden Chair',
      'location': 'Nashville, TN',
      'image': 'https://picsum.photos/seed/buy_chair/300',
    },
    {
      'name': 'Travel Suitcase',
      'location': 'Miami, FL',
      'image': 'https://picsum.photos/seed/buy_suitcase/300',
    },
    {
      'name': 'Bluetooth Speaker',
      'location': 'Denver, CO',
      'image': 'https://picsum.photos/seed/buy_speaker/300',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final bool isSeller = _isSellerAccount && _mode == _ProfileMode.seller;
    final List<Map<String, String>> items = isSeller
        ? _myListings
        : _recentPurchases;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 34,
                      backgroundImage: NetworkImage(
                        'https://i.pravatar.cc/150?img=21',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alex Morgan',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isSeller ? 'Campus Seller' : 'Campus Buyer',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Colors.grey[700]),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _StatChip(
                                label: isSeller ? 'Listings' : 'Purchases',
                                value: isSeller ? '12' : '48',
                              ),
                              const SizedBox(width: 8),
                              _StatChip(
                                label: isSeller ? 'Sold' : 'Saved',
                                value: isSeller ? '39' : '22',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isSellerAccount)
              SegmentedButton<_ProfileMode>(
                segments: const [
                  ButtonSegment<_ProfileMode>(
                    value: _ProfileMode.seller,
                    icon: Icon(Icons.storefront_outlined),
                    label: Text('Seller'),
                  ),
                  ButtonSegment<_ProfileMode>(
                    value: _ProfileMode.buyer,
                    icon: Icon(Icons.shopping_bag_outlined),
                    label: Text('Buyer'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.first;
                  });
                },
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Upgrade to a seller account to start posting listings.',
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _isSellerAccount = true;
                            _mode = _ProfileMode.seller;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Account upgraded to seller.'),
                            ),
                          );
                        },
                        child: const Text('Upgrade'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              isSeller ? 'My Listings' : 'Recent Purchases',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _myListings.length,
              gridDelegate: kProductGridDelegate,
              itemBuilder: (context, index) {
                final item = items[index];
                return ProductGridCard(
                  name: item['name']!,
                  location: item['location']!,
                  imageUrl: item['image']!,
                );
              },
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      isSeller
                          ? Icons.analytics_outlined
                          : Icons.receipt_long_outlined,
                    ),
                    title: Text(isSeller ? 'Sales Insights' : 'Orders'),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                  const Divider(height: 1),
                  const ListTile(
                    leading: Icon(Icons.help_outline_rounded),
                    title: Text('Help & Support'),
                    trailing: Icon(Icons.chevron_right),
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$value $label',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
    );
  }
}
