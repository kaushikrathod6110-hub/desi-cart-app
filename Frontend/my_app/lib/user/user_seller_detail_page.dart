import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_auth_session.dart';
import 'package:my_app/user/user_product_detail_page.dart';
import 'package:my_app/user/user_wishlist_service.dart';

import 'user_cart_page.dart';
import 'user_category_page.dart';
import 'user_home_page.dart';

class SellerDetailPage extends StatefulWidget {
  final int sellerId;
  final String sellerName;
  final List wishlist;
  final Function onUpdate;

  const SellerDetailPage({
    super.key,
    required this.sellerId,
    required this.sellerName,
    required this.wishlist,
    required this.onUpdate,
  });

  @override
  State<SellerDetailPage> createState() => _SellerDetailPageState();
}

Future<Map<String, String>> getHeaders() async {
  final token = await TokenStorage().getAccessToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

class _SellerDetailPageState extends State<SellerDetailPage> {
  int? currentUserId;
  int currentIndex = 1;

  Map<String, dynamic>? seller;
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
    await fetchData();
    if (mounted) setState(() {});
  }

  Future<void> fetchData() async {
    final sellerRes = await http.get(
      ApiConfig.uri('/api/sellers/public/${widget.sellerId}'),
      headers: await getHeaders(),
    );

    final productRes = await http.get(
      ApiConfig.uri('/api/sellers/public/${widget.sellerId}/products'),
      headers: await getHeaders(),
    );

    seller = sellerRes.statusCode == 200 ? Map<String, dynamic>.from(jsonDecode(sellerRes.body)) : null;
    products = productRes.statusCode == 200 ? jsonDecode(productRes.body) : [];

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> refreshWishlist() async {
    final storedWishlist = await UserWishlistService.load(currentUserId);
    widget.wishlist
      ..clear()
      ..addAll(storedWishlist);
    if (mounted) setState(() {});
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

  String _sellerLogoUrl() {
    final directUrl = (seller?['store_logo_url'] ?? '').toString().trim();
    if (directUrl.isNotEmpty) return _normalizeImage(directUrl);

    final raw = (seller?['store_logo'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (!raw.contains('/')) return '${ApiConfig.baseUrl}/api/seller/logo/$raw';
    return ApiConfig.fileUrl(raw);
  }

  String _productImageUrl(Map product) {
    final dynamic imageList = product['product_images'] ?? product['prod_images'];
    if (imageList is List && imageList.isNotEmpty) {
      return _normalizeImage(imageList.first);
    }
    return _normalizeImage(product['prod_image_url'] ?? product['prod_image']);
  }

  Widget _buildSellerAvatar({double size = 100}) {
    final imageUrl = _sellerLogoUrl();
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.blue.shade100,
        child: Icon(Icons.store, color: Colors.blue, size: size * 0.45),
      );
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.blue.shade100,
            child: Icon(Icons.store, color: Colors.blue, size: size * 0.45),
          );
        },
      ),
    );
  }


  bool _isOutOfStock(Map product) {
    final status = (product['stock_status'] ?? '').toString().toLowerCase();
    final qty = int.tryParse((product['stock_quantity'] ?? '0').toString()) ?? 0;
    return status == 'out of stock' || qty <= 0;
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
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return SizedBox(
          width: width,
          height: height,
          child: Icon(Icons.image_outlined, color: Colors.grey, size: width * 0.5),
        );
      },
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

  void onNavTap(int index) {
    if (index == currentIndex) return;

    if (index == 0) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryPage(
            wishlist: widget.wishlist,
            onUpdate: widget.onUpdate,
          ),
        ),
      );
    } else if (index == 3) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CartScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(widget.sellerName),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : seller == null
          ? const Center(child: Text('Seller not found'))
          : SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 520;
                  final avatarSize = isCompact ? 88.0 : 100.0;

                  final avatar = Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 6),
                      ],
                    ),
                    child: _buildSellerAvatar(size: avatarSize),
                  );

                  final detailsCard = Container(
                    width: isCompact ? double.infinity : null,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(color: Colors.grey.withOpacity(0.2), blurRadius: 6),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seller!['seller_name']?.toString() ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(seller!['shop_name']?.toString() ?? ''),
                        const SizedBox(height: 4),
                        Text(seller!['shop_address']?.toString() ?? ''),
                        const SizedBox(height: 6),
                        Text(seller!['seller_mobile']?.toString() ?? ''),
                      ],
                    ),
                  );

                  if (isCompact) {
                    return Column(
                      children: [avatar, const SizedBox(height: 12), detailsCard],
                    );
                  }

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [avatar, const SizedBox(width: 12), Expanded(child: detailsCard)],
                  );
                },
              ),
            ),
            const SizedBox(height: 25),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Products',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
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
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
                    final isOutOfStock = _isOutOfStock(product);

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
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: onNavTap,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Sellers'),
          BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Category'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Cart'),
        ],
      ),
    );
  }
}