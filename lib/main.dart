import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_base_url.dart';
import 'api_routes.dart';
import 'chats_page.dart';
import 'components/product_grid_card.dart';
import 'components/studket_app_bar.dart';
import 'product_details_page.dart';
import 'user_profile_page.dart';

void main() {
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
      home: const MyHomePage(title: 'Studket'),
    );
  }
}

class ProductItem {
  const ProductItem({
    required this.id,
    required this.name,
    required this.priceLabel,
    required this.location,
    required this.imageUrl,
    required this.description,
  });

  final String id;
  final String name;
  final String priceLabel;
  final String location;
  final String imageUrl;
  final String description;

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final String name = (json['name'] ?? json['title'] ?? 'Untitled Product')
        .toString();
    final String location =
        (json['location'] ?? json['address'] ?? 'Location unavailable')
            .toString();
    final String imageUrl =
        (json['image'] ??
                json['image_url'] ??
                json['thumbnail'] ??
                'https://picsum.photos/seed/default_product/300')
            .toString();
    final String description =
        (json['description'] ??
                '$name in excellent condition. Message the seller for details.')
            .toString();

    return ProductItem(
      id: (json['id'] ?? json['product_id'] ?? name.hashCode).toString(),
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int currentPageIndex = 0;
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

  bool _isLoading = true;
  String? _loadError;
  List<ProductItem> _products = const <ProductItem>[];

  @override
  void initState() {
    super.initState();
    _fetchProducts();
  }

  Future<void> _fetchProducts({bool showLoader = true}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    } else {
      setState(() {
        _loadError = null;
      });
    }

    try {
      final Uri uri = ApiRoutes.products(port: 8088);
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

      final List<ProductItem> parsed = decoded
          .whereType<Map>()
          .map((item) => ProductItem.fromJson(Map<String, dynamic>.from(item)))
          .toList();

      if (!mounted) return;
      setState(() {
        _products = parsed;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loadError = 'Request timed out. Pull to refresh and try again.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load products. Pull to refresh and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshProducts() async {
    await _fetchProducts(showLoader: false);
  }

  void _openProductDetails(ProductItem product, int index) {
    final String seed = product.name
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
          productName: product.name,
          productPrice: product.priceLabel,
          productLocation: product.location,
          productDescription: product.description,
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
                        child: Builder(
                          builder: (context) {
                            if (_isLoading) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (_loadError != null && _products.isEmpty) {
                              return ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height *
                                        0.4,
                                    child: Center(
                                      child: Text(
                                        _loadError!,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }

                            if (_products.isEmpty) {
                              return ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(
                                    height: 280,
                                    child: Center(
                                      child: Text('No products found.'),
                                    ),
                                  ),
                                ],
                              );
                            }

                            return GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _products.length,
                              gridDelegate: kProductGridDelegate,
                              itemBuilder: (context, index) {
                                final ProductItem product = _products[index];
                                return ProductGridCard(
                                  name: product.name,
                                  price: product.priceLabel,
                                  location: product.location,
                                  imageUrl: product.imageUrl,
                                  onTap: () {
                                    _openProductDetails(product, index);
                                  },
                                );
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
