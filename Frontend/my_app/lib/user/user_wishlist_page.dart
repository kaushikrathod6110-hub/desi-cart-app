
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_product_detail_page.dart';
import 'package:my_app/user/user_wishlist_service.dart';

class WishlistPage extends StatefulWidget {
  final List wishlist;
  final Function onUpdate;
  final int? currentUserId;

  const WishlistPage({
    super.key,
    required this.wishlist,
    required this.onUpdate,
    this.currentUserId,
  });

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  bool isRefreshing = true;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _initWishlist();
  }

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _initWishlist() async {
    setState(() => isRefreshing = true);

    try {
      final incoming = widget.wishlist
          .where((item) => item is Map)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (incoming.isNotEmpty) {
        items = incoming;
      } else {
        final stored = await UserWishlistService.load(widget.currentUserId);
        items = stored
            .where((item) => item is Map)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }

      if (widget.currentUserId != null) {
        await UserWishlistService.save(widget.currentUserId, items);
      }

      if (mounted) setState(() {});
      await _refreshStatuses();
    } finally {
      if (mounted) {
        setState(() => isRefreshing = false);
      }
    }
  }

  Future<void> _refreshStatuses() async {
    if (items.isEmpty) return;

    final refreshed = <Map<String, dynamic>>[];

    for (final item in items) {
      final prodId = item['prod_id'];
      final sellerId = item['seller_id'];

      try {
        final response = await http
            .get(
          ApiConfig.uri(
            '/api/products/public/$prodId',
            queryParameters: sellerId == null ? null : {'seller_id': '$sellerId'},
          ),
          headers: await getHeaders(),
        )
            .timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final latest = Map<String, dynamic>.from(jsonDecode(response.body));
          refreshed.add({...item, ...latest});
        } else {
          refreshed.add(item);
        }
      } catch (_) {
        refreshed.add(item);
      }
    }

    items = refreshed;
    widget.wishlist
      ..clear()
      ..addAll(refreshed);

    if (widget.currentUserId != null) {
      await UserWishlistService.save(widget.currentUserId, refreshed);
    }

    if (mounted) setState(() {});
    widget.onUpdate();
  }

  bool isOutOfStock(Map product) {
    final status = (product['stock_status'] ?? '').toString().toLowerCase();
    final qty = int.tryParse((product['stock_quantity'] ?? '0').toString()) ?? 0;
    return status == 'out of stock' || qty <= 0;
  }

  String getImage(String img) {
    if (img.contains(',')) {
      img = img.split(',')[0];
    }
    if (img.startsWith('http')) return img;
    if (img.trim().isEmpty) return '';
    return ApiConfig.fileUrl(img);
  }

  Widget buildProductImage(String img) {
    final imageUrl = getImage(img);
    if (imageUrl.isEmpty) {
      return const SizedBox(
        width: 80,
        height: 80,
        child: Icon(Icons.image_outlined, color: Colors.grey, size: 40),
      );
    }
    return Image.network(
      imageUrl,
      width: 80,
      height: 80,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return const SizedBox(
          width: 80,
          height: 80,
          child: Icon(Icons.image_outlined, color: Colors.grey, size: 40),
        );
      },
    );
  }

  Future<void> removeFromWishlist(Map product) async {
    final next = await UserWishlistService.remove(
      userId: widget.currentUserId,
      wishlist: items,
      prodId: product['prod_id'],
      sellerId: product['seller_id'],
    );

    items = next
        .where((item) => item is Map)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    widget.wishlist
      ..clear()
      ..addAll(items);

    if (mounted) setState(() {});
    widget.onUpdate();
  }

  Future<void> addToCart(Map product) async {
    final response = await http.post(
      ApiConfig.uri('/add_to_cart'),
      headers: await getHeaders(),
      body: jsonEncode({
        'user_id': widget.currentUserId,
        'prod_id': product['prod_id'],
        if (product['seller_id'] != null) 'seller_id': product['seller_id'],
        'quantity': 1,
      }),
    );

    if (!mounted) return;

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to cart successfully')),
      );
    } else {
      String message = 'Unable to add to cart';
      try {
        final data = jsonDecode(response.body);
        message = (data['message'] ?? data['error'] ?? message).toString();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3edf7),
      appBar: AppBar(
        title: const Text('My Wishlist'),
        backgroundColor: Colors.blue,
      ),
      body: isRefreshing
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? const Center(child: Text('Your wishlist is empty'))
          : RefreshIndicator(
        onRefresh: _refreshStatuses,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1100
                ? 5
                : width >= 850
                ? 4
                : width >= 600
                ? 3
                : 2;
            final childAspectRatio = width < 420 ? 0.60 : 0.76;

            return GridView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: items.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final product = Map<String, dynamic>.from(items[index]);
                final outOfStock = isOutOfStock(product);

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
                    await _initWishlist();
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
                            onTap: () => removeFromWishlist(product),
                            child: const Icon(Icons.favorite, color: Colors.red),
                          ),
                        ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Center(
                                child: buildProductImage((product['prod_image'] ?? '').toString()),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              (product['prod_name'] ?? '').toString(),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '₹ ${product['prod_price']}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              outOfStock ? 'Out of Stock' : 'Available',
                              style: TextStyle(
                                color: outOfStock ? Colors.red : Colors.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: outOfStock ? null : () => addToCart(product),
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(38),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: FittedBox(
                                  child: Text(outOfStock ? 'Out of Stock' : 'ADD'),
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
      ),
    );
  }
}