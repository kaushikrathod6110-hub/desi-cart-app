import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'edit_product_page.dart';
import 'package:my_app/api_config.dart';
import '../screens/login_page.dart';
import '../screens/token_storage.dart';

class MyProductsPage extends StatefulWidget {
  final String? filterMode;

  const MyProductsPage({super.key, this.filterMode});

  @override
  State<MyProductsPage> createState() => _MyProductsPageState();
}

class _MyProductsPageState extends State<MyProductsPage> {
  final List<Map<String, dynamic>> products = [];
  final TextEditingController searchController = TextEditingController();

  bool _alertShown = false;
  String searchText = "";
  bool isLoading = true;
  String errorMessage = "";

  @override
  void initState() {
    super.initState();
    fetchProducts();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchProducts() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final storage = TokenStorage();
      final token = await storage.getAccessToken();

      if (token == null || token.isEmpty) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
        return;
      }

      final response = await http.get(
        ApiConfig.uri(
          "/api/seller/products",
          queryParameters: {
            if (searchText.trim().isNotEmpty) "search": searchText.trim(),
            if (widget.filterMode != null && widget.filterMode!.isNotEmpty)
              "filter_mode": widget.filterMode!,
          },
        ),
        headers: {
          "Authorization": "Bearer $token",
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["success"] == true) {
        final List<dynamic> fetchedProducts = data["products"] ?? [];

        products.clear();
        products.addAll(
          fetchedProducts.map((e) => Map<String, dynamic>.from(e)).toList(),
        );

        if (mounted) {
          setState(() {
            isLoading = false;
          });

          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showLowStockAlert();
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 422) {
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      } else {
        setState(() {
          isLoading = false;
          errorMessage = data["message"] ?? "Failed to load products";
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Error: $e";
      });
    }
  }

  void _showLowStockAlert() {
    if (_alertShown) return;

    bool hasLowStock = products.any(
          (product) => (num.tryParse(product["stock"].toString()) ?? 0) <= 5,
    );

    if (hasLowStock) {
      _alertShown = true;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text("Low Stock Alert"),
            ],
          ),
          content: const Text(
            "Some grocery products are low in stock. Please restock them to avoid order issues.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "OK",
                style: TextStyle(color: Color(0xFF2196F3)),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _productImage(Map<String, dynamic> product) {
    if (product["images"] != null &&
        product["images"] is List &&
        product["images"].isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          product["images"][0],
          width: 70,
          height: 70,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.image_not_supported,
                color: Colors.blueAccent,
                size: 32,
              ),
            );
          },
        ),
      );
    }

    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.image_not_supported,
        color: Colors.blueAccent,
        size: 32,
      ),
    );
  }

  Widget _buildRatingRow(Map<String, dynamic> product) {
    final double avgRating =
        double.tryParse((product["avg_rating"] ?? 0).toString()) ?? 0.0;
    final int reviewCount =
        int.tryParse((product["review_count"] ?? 0).toString()) ?? 0;

    if (reviewCount <= 0) {
      return const Text(
        "No ratings yet",
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey,
        ),
      );
    }

    return Row(
      children: [
        const Icon(Icons.star, size: 16, color: Colors.amber),
        const SizedBox(width: 4),
        Text(
          avgRating.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          "($reviewCount review${reviewCount == 1 ? '' : 's'})",
          style: const TextStyle(
            fontSize: 13,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String pageTitle = widget.filterMode == "low_stock"
        ? "Low Stock Products"
        : widget.filterMode == "out_of_stock"
        ? "Out of Stock Products"
        : "My Products";

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          pageTitle,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: const Color(0xFF2196F3),
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: const Color(0xFF2196F3),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: TextField(
              controller: searchController,
              onChanged: (value) {
                setState(() {
                  searchText = value;
                });
                fetchProducts();
              },
              decoration: InputDecoration(
                hintText: "Search products.",
                prefixIcon: const Icon(
                  Icons.search,
                  color: Colors.blueAccent,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage.isNotEmpty
                ? Center(
              child: Text(
                errorMessage,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.red,
                ),
              ),
            )
                : products.isEmpty
                ? const Center(
              child: Text(
                "No products found",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                final double stock =
                    double.tryParse(product["stock"].toString()) ??
                        0;
                final bool isLowStock = stock <= 5 && stock > 0;
                final bool isOutOfStock = stock <= 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12.withOpacity(0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _productImage(product),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              product["name"].toString(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Category: ${product["category"]}",
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildRatingRow(product),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "₹${product["price"]}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  "Stock: ${product["stock"]}",
                                  style: TextStyle(
                                    color: isOutOfStock
                                        ? Colors.red
                                        : isLowStock
                                        ? Colors.orange
                                        : Colors.green,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () async {
                                  final updatedProduct =
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EditProductPage(
                                            product: Map<String,
                                                dynamic>.from(
                                              product,
                                            ),
                                          ),
                                    ),
                                  );

                                  if (updatedProduct != null) {
                                    fetchProducts();
                                  }
                                },
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blueAccent,
                                  size: 18,
                                ),
                                label: const Text(
                                  "Edit",
                                  style: TextStyle(
                                    color: Colors.blueAccent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(0, 0),
                                  tapTargetSize:
                                  MaterialTapTargetSize
                                      .shrinkWrap,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}