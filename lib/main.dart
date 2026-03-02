import 'package:flutter/material.dart';
import 'product_details_page.dart';
import 'chats_page.dart';
import 'user_profile_page.dart';
import 'components/product_grid_card.dart';
import 'components/studket_app_bar.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Studket',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
      ),
      home: const MyHomePage(title: 'Studket'),
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
  final ScrollController _scrollController = ScrollController();
  bool _isLoadingMore = false;
  final List<String> _categories = const [
    'Electronics',
    'Home',
    'Fashion',
    'Sports',
    'Books',
    'Beauty',
  ];
  final Set<String> _selectedCategories = <String>{};
  final List<String> _sellerNames = const [
    'Ava Thompson',
    'Liam Carter',
    'Noah Reyes',
    'Mia Brooks',
    'Emma Gray',
  ];
  final List<Map<String, String>> _seedProducts = [
    {
      'name': 'Wireless Earbuds',
      'price': '\$59',
      'location': 'San Francisco, CA',
      'image': 'https://picsum.photos/seed/earbuds/200',
    },
    {
      'name': 'Vintage Desk Lamp',
      'price': '\$34',
      'location': 'Austin, TX',
      'image': 'https://picsum.photos/seed/lamp/200',
    },
    {
      'name': 'Minimal Backpack',
      'price': '\$42',
      'location': 'Seattle, WA',
      'image': 'https://picsum.photos/seed/backpack/200',
    },
    {
      'name': 'Ceramic Coffee Mug',
      'price': '\$12',
      'location': 'Chicago, IL',
      'image': 'https://picsum.photos/seed/mug/200',
    },
    {
      'name': 'Running Shoes',
      'price': '\$68',
      'location': 'Portland, OR',
      'image': 'https://picsum.photos/seed/shoes/200',
    },
    {
      'name': 'Smart Watch',
      'price': '\$95',
      'location': 'Boston, MA',
      'image': 'https://picsum.photos/seed/watch/200',
    },
    {
      'name': 'Bluetooth Speaker',
      'price': '\$47',
      'location': 'Denver, CO',
      'image': 'https://picsum.photos/seed/speaker/200',
    },
    {
      'name': 'Wooden Chair',
      'price': '\$80',
      'location': 'Nashville, TN',
      'image': 'https://picsum.photos/seed/chair/200',
    },
    {
      'name': 'Travel Suitcase',
      'price': '\$73',
      'location': 'Miami, FL',
      'image': 'https://picsum.photos/seed/suitcase/200',
    },
    {
      'name': 'Laptop Stand',
      'price': '\$26',
      'location': 'New York, NY',
      'image': 'https://picsum.photos/seed/stand/200',
    },
  ];
  late final List<Map<String, String>> products = List.of(_seedProducts);

  Future<void> _refreshProducts() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    setState(() {
      products.shuffle();
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreProducts();
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 700));

    final int startId = products.length + 1;
    final List<Map<String, String>> newProducts = List.generate(10, (index) {
      final base = _seedProducts[index % _seedProducts.length];
      final id = startId + index;
      return {
        'name': '${base['name']} $id',
        'price': base['price']!,
        'location': base['location']!,
        'image': 'https://picsum.photos/seed/product_$id/200',
      };
    });

    if (!mounted) return;
    setState(() {
      products.addAll(newProducts);
      _isLoadingMore = false;
    });
  }

  void _openProductDetails(Map<String, String> product, int index) {
    final String seed = product['name']!
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll(',', '');
    final List<String> gallery = List.generate(
      4,
      (i) => 'https://picsum.photos/seed/${seed}_${index}_$i/900',
    );
    final String sellerName = _sellerNames[index % _sellerNames.length];
    final double rating = 3.5 + ((index % 4) * 0.5);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProductDetailsPage(
          productName: product['name']!,
          productPrice: product['price']!,
          productLocation: product['location']!,
          productDescription:
              '${product['name']} in excellent condition. Lightly used and fully functional. '
              'Pickup available around ${product['location']} or message to arrange delivery.',
          imageUrls: gallery,
          sellerName: sellerName,
          sellerAvatarUrl: 'https://i.pravatar.cc/150?img=${(index % 70) + 1}',
          sellerRating: rating,
        ),
      ),
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey[200]),
        ),
      ),
      body: Center(
        child: currentPageIndex == 0
            ? Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Material(
                      elevation: 2,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search products',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.tune),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 40,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _categories.map((category) {
                            final isSelected = _selectedCategories.contains(
                              category,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(category),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedCategories.add(category);
                                    } else {
                                      _selectedCategories.remove(category);
                                    }
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refreshProducts,
                        child: GridView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: products.length + (_isLoadingMore ? 2 : 0),
                          gridDelegate: kProductGridDelegate,
                          itemBuilder: (context, index) {
                            if (index >= products.length) {
                              return const Card(
                                child: Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              );
                            }
                            final product = products[index];
                            return ProductGridCard(
                              name: product['name']!,
                              price: product['price'],
                              location: product['location']!,
                              imageUrl: product['image']!,
                              onTap: () {
                                _openProductDetails(product, index);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const UserProfilePage(),
      ),
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
            label: "Home",
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: "Profile",
          ),
        ],
      ),
      floatingActionButton: Stack(
        clipBehavior: Clip.none,
        children: [
          FloatingActionButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ChatsPage()));
            },
            child: const Icon(Icons.chat_bubble_outline),
          ),
          Positioned(
            right: -2,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              constraints: const BoxConstraints(minWidth: 22),
              child: const Text(
                '3',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
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
