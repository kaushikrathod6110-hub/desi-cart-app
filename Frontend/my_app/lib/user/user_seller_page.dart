import "package:my_app/api_config.dart";
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/user/user_seller_detail_page.dart';
import 'package:my_app/user/user_auth_session.dart';

import 'package:my_app/screens/token_storage.dart';
import 'user_cart_page.dart';
import 'user_category_page.dart';
import 'user_home_page.dart';

class SellerPage extends StatefulWidget {
  final List wishlist;
  final Function onUpdate;

  const SellerPage({
    super.key,
    required this.wishlist,
    required this.onUpdate,
  });

  @override
  State<SellerPage> createState() => _SellerPageState();
}

Future<Map<String, String>> getHeaders() async {
  final token = await TokenStorage().getAccessToken();

  return {
    "Content-Type": "application/json",
    if (token != null) "Authorization": "Bearer $token",
  };
}

class _SellerPageState extends State<SellerPage> {
  int currentIndex = 1;
  int? currentUserId;
  String searchQuery = '';
  List sellers = [];
  List filteredSellers = [];
  bool isLoading = true;

  bool get _isNearbySearch {
    final normalized = searchQuery.toLowerCase().replaceAll('-', ' ').trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized == 'seller near by me' ||
        normalized == 'sellers near by me' ||
        normalized == 'seller nearby me' ||
        normalized == 'sellers nearby me' ||
        normalized == 'near by me' ||
        normalized == 'nearby me';
  }

  Future fetchSellers() async {
    final params = <String, String>{};
    if (searchQuery.trim().isNotEmpty) {
      params['search'] = searchQuery.trim();
    }
    if (_isNearbySearch && currentUserId != null) {
      params['nearby_user_id'] = currentUserId.toString();
      params['nearby_only'] = '1';
    }

    final res = await http.get(
      ApiConfig.uri('/api/sellers/public', queryParameters: params.isEmpty ? null : params),
      headers: await getHeaders(),
    );

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      setState(() {
        sellers = decoded is List ? decoded : [];
        filteredSellers = List.from(sellers);
        isLoading = false;
      });
    } else {
      setState(() {
        sellers = [];
        filteredSellers = [];
        isLoading = false;
      });
    }
  }

  Future<void> searchSeller(String query) async {
    searchQuery = query;
    await fetchSellers();
  }

  String _sellerLogoUrl(Map seller) {
    final directUrl = (seller["store_logo_url"] ?? '').toString().trim();
    if (directUrl.isNotEmpty) return directUrl;

    final raw = (seller["store_logo"] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (!raw.contains('/')) return '${ApiConfig.baseUrl}/api/seller/logo/$raw';
    return ApiConfig.fileUrl(raw);
  }

  Widget _buildSellerAvatar(Map seller, {double size = 64}) {
    final imageUrl = _sellerLogoUrl(seller);

    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.blue.shade100,
        child: Icon(Icons.store, color: Colors.blue, size: size * 0.5),
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
            child: Icon(Icons.store, color: Colors.blue, size: size * 0.5),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    currentUserId = await UserAuthSession.getCurrentUserId();
    await fetchSellers();
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
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
        MaterialPageRoute(
          builder: (_) => const CartScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _goToHome();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.blue,
          automaticallyImplyLeading: false,
          title: Text(_isNearbySearch ? "Nearby Sellers" : "Sellers"),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextField(
                onChanged: (value) {
                  searchSeller(value);
                },
                decoration: InputDecoration(
                  hintText: "Search seller...",
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : filteredSellers.isEmpty
            ? const Center(child: Text("No sellers found"))
            : LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final crossAxisCount = width >= 1200
                ? 6
                : width >= 900
                ? 4
                : 3;
            final childAspectRatio = width < 420
                ? 0.50
                : width < 600
                ? 0.56
                : 0.90;

            return GridView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: filteredSellers.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final seller = filteredSellers[index];

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SellerDetailPage(
                          sellerId: seller["seller_id"],
                          sellerName: seller["seller_name"],
                          wishlist: widget.wishlist,
                          onUpdate: widget.onUpdate,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildSellerAvatar(seller, size: width < 600 ? 48 : 64),
                        const SizedBox(height: 6),
                        Flexible(
                          child: Text(
                            seller["seller_name"]?.toString() ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              height: 1.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Flexible(
                          child: Text(
                            seller["shop_name"]?.toString() ?? '',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          currentIndex: currentIndex,
          onTap: onNavTap,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.store), label: "Sellers"),
            BottomNavigationBarItem(icon: Icon(Icons.category), label: "Category"),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Cart"),
          ],
        ),
      ),
    );
  }
}