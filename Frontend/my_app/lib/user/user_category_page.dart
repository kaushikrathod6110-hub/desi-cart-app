import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_cart_page.dart';
import 'package:my_app/user/user_home_page.dart';
import 'package:my_app/user/user_product_page.dart';
import 'package:my_app/user/user_seller_page.dart';

class CategoryPage extends StatefulWidget {
  final List wishlist;
  final Function onUpdate;

  const CategoryPage({
    super.key,
    required this.wishlist,
    required this.onUpdate,
  });

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  List categories = [];
  List filteredCategories = [];
  bool isLoading = true;
  int currentIndex = 2;

  @override
  void initState() {
    super.initState();
    fetchCategories();
  }

  Future<void> fetchCategories() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/api/categories/public'),
        headers: await widget.getHeaders(),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        setState(() {
          categories = decoded is List ? decoded : [];
          filteredCategories = List.from(categories);
          isLoading = false;
        });
      } else {
        setState(() {
          categories = [];
          filteredCategories = [];
          isLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        categories = [];
        filteredCategories = [];
        isLoading = false;
      });
    }
  }

  void searchCategory(String query) {
    final normalized = query.trim().toLowerCase();
    final results = categories.where((cat) {
      final name = (cat['category_name'] ?? '').toString().toLowerCase();
      final description = (cat['description'] ?? '').toString().toLowerCase();
      return name.contains(normalized) || description.contains(normalized);
    }).toList();

    setState(() {
      filteredCategories = results;
    });
  }

  String _categoryImageUrl(Map category) {
    final raw = (category['category_image_url'] ?? category['category_image'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.fileUrl(raw);
  }

  Widget _buildCategoryAvatar(Map category) {
    final imageUrl = _categoryImageUrl(category);

    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: 25,
        backgroundColor: Colors.deepPurple.shade100,
        child: const Icon(Icons.category, color: Colors.deepPurple),
      );
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return CircleAvatar(
            radius: 25,
            backgroundColor: Colors.deepPurple.shade100,
            child: const Icon(Icons.category, color: Colors.deepPurple),
          );
        },
      ),
    );
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
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SellerPage(
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
          title: const Text('Categories'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(70),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: TextField(
                onChanged: searchCategory,
                decoration: InputDecoration(
                  hintText: 'Search category...',
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: filteredCategories.length,
          itemBuilder: (context, index) {
            final category = Map<String, dynamic>.from(filteredCategories[index]);

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductPage(
                      categoryId: category['category_id'],
                      categoryName: (category['category_name'] ?? '').toString(),
                      wishlist: widget.wishlist,
                      onUpdate: widget.onUpdate,
                    ),
                  ),
                );
              },
              child: Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: _buildCategoryAvatar(category),
                  title: Text((category['category_name'] ?? '').toString()),
                  subtitle: Text((category['description'] ?? '').toString()),
                  trailing: const Icon(Icons.arrow_forward_ios),
                ),
              ),
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
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Sellers'),
            BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Category'),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Cart'),
          ],
        ),
      ),
    );
  }
}