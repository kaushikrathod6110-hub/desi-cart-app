import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_auth_session.dart';
import 'package:my_app/user/user_notification_page.dart';
import 'package:my_app/user/user_product_detail_page.dart';
import 'package:my_app/user/user_profile_page.dart';
import 'package:my_app/user/user_wishlist_page.dart';
import 'package:my_app/user/user_wishlist_service.dart';

class ProductPage extends StatefulWidget {
  final int categoryId;
  final String categoryName;
  final List wishlist;
  final Function onUpdate;

  const ProductPage({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.wishlist,
    required this.onUpdate,
  });

  @override
  State<ProductPage> createState() => _ProductPageState();
}

Future<Map<String, String>> getHeaders() async {
  final token = await TokenStorage().getAccessToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

class _ProductPageState extends State<ProductPage> {
  int? currentUserId;
  List products = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    currentUserId = await UserAuthSession.getCurrentUserId();
    final storedWishlist = await UserWishlistService.load(currentUserId);
    widget.wishlist
      ..clear()
      ..addAll(storedWishlist);
    await fetchProducts();
    if (mounted) setState(() {});
  }

  Future<void> refreshWishlist() async {
    final storedWishlist = await UserWishlistService.load(currentUserId);
    widget.wishlist
      ..clear()
      ..addAll(storedWishlist);
    if (mounted) setState(() {});
  }

  Future<void> fetchProducts() async {
    final response = await http.get(
      ApiConfig.uri('/api/products/public', queryParameters: {'category_id': widget.categoryId}),
      headers: await getHeaders(),
    );

    if (response.statusCode == 200) {
      products = jsonDecode(response.body);
    } else {
      products = [];
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> addToCart(int prodId, {int? sellerId}) async {
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login again')),
      );
      return;
    }

    final response = await http.post(
      ApiConfig.uri('/add_to_cart'),
      headers: await getHeaders(),
      body: jsonEncode({
        'user_id': currentUserId,
        'prod_id': prodId,
        if (sellerId != null) 'seller_id': sellerId,
        'quantity': 1,
      }),
    );

    if (response.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to cart successfully')),
      );
    }
  }

  String _normalizeImage(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.fileUrl(raw);
  }

  String _productImageUrl(Map product) {
    final dynamic imageList = product['product_images'] ?? product['prod_images'];
    if (imageList is List && imageList.isNotEmpty) {
      return _normalizeImage(imageList.first);
    }
    return _normalizeImage(product['prod_image_url'] ?? product['prod_image'] ?? product['image']);
  }

  Widget _buildProductImage(Map product, {double width = 80, double height = 80}) {
    final imageUrl = _productImageUrl(product);
    if (imageUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Icon(Icons.image_outlined, color: Colors.grey, size: width * 0.5),
      );
    }

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return SizedBox(
          width: width,
          height: height,
          child: Icon(Icons.image_outlined, color: Colors.grey, size: width * 0.5),
        );
      },
    );
  }

  Future<void> openWishlist() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WishlistPage(
          wishlist: widget.wishlist,
          currentUserId: currentUserId,
          onUpdate: () {
            setState(() {});
          },
        ),
      ),
    );
    await refreshWishlist();
  }

  void openNotification() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationPage()),
    );
  }

  Future<void> openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  Future<void> toggleWishlist(Map product) async {
    final next = await UserWishlistService.toggle(
      userId: currentUserId,
      wishlist: widget.wishlist,
      product: Map<String, dynamic>.from(product),
    );
    widget.wishlist
      ..clear()
      ..addAll(next);

    if (mounted) setState(() {});
    widget.onUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: openNotification,
          ),
          IconButton(
            icon: Icon(
              widget.wishlist.isEmpty ? Icons.favorite_border : Icons.favorite,
              color: widget.wishlist.isEmpty ? Colors.white : Colors.red.shade100,
            ),
            onPressed: openWishlist,
          ),
          IconButton(
            icon: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, color: Colors.blue),
            ),
            onPressed: openProfile,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final crossAxisCount = width >= 1200
              ? 6
              : width >= 900
              ? 4
              : width >= 600
              ? 3
              : 2;
          final childAspectRatio = width < 420
              ? 0.60
              : width < 600
              ? 0.68
              : 0.82;

          return GridView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: products.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: childAspectRatio,
            ),
            itemBuilder: (context, index) {
              final product = Map<String, dynamic>.from(products[index]);
              final exists = UserWishlistService.contains(widget.wishlist, product['prod_id']);
              final isOutOfStock =
                  ((product['stock_quantity'] ?? 0) as num) <= 0 ||
                      (product['stock_status']?.toString().toLowerCase() == 'out of stock');

              return GestureDetector(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductDetailPage(
                        prodId: product['prod_id'],
                        wishlist: widget.wishlist,
                        onUpdate: widget.onUpdate,
                      ),
                    ),
                  );
                  await refreshWishlist();
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 5,
                        right: 5,
                        child: GestureDetector(
                          onTap: () => toggleWishlist(product),
                          child: Icon(
                            exists ? Icons.favorite : Icons.favorite_border,
                            color: exists ? Colors.red : Colors.grey,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(child: Center(child: _buildProductImage(product))),
                          const SizedBox(height: 8),
                          Text(
                            product['prod_name']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '₹ ${product['prod_price']}',
                            style: const TextStyle(color: Colors.green),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          if (isOutOfStock)
                            const Text(
                              'Out of Stock',
                              style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isOutOfStock
                                  ? null
                                  : () => addToCart(
                                product['prod_id'],
                                sellerId: product['seller_id'],
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                minimumSize: const Size.fromHeight(38),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: FittedBox(
                                child: Text(isOutOfStock ? 'Out of Stock' : 'ADD'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}