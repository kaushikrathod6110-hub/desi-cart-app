import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/api_config.dart';
import '../screens/login_page.dart';
import '../screens/token_storage.dart';
import 'order.dart';
import 'seller_profile.dart';
import 'add_product.dart';
import 'my_products_page.dart';
import 'seller_reports_page.dart';
import 'seller_feedback_page.dart';

class SellerHomePage extends StatefulWidget {
  final String? token;

  const SellerHomePage({super.key, this.token});

  @override
  State<SellerHomePage> createState() => _SellerHomePageState();
}

class _SellerHomePageState extends State<SellerHomePage> {
  bool isLoading = true;
  String errorMessage = "";
  String? accessToken;
  bool isGuest = false;

  Map<String, dynamic>? sellerData;
  Map<String, dynamic>? summaryData;
  List<dynamic> recentProducts = [];
  List<dynamic> recentOrders = [];

  @override
  void initState() {
    super.initState();
    loadTokenAndDashboard();
  }

  Future<void> loadTokenAndDashboard() async {
    try {
      final storage = TokenStorage();
      accessToken = widget.token ?? await storage.getAccessToken();

      if (accessToken == null || accessToken!.isEmpty) {
        setState(() {
          isGuest = true;
          isLoading = false;
          errorMessage = "";
        });
        return;
      }

      await fetchDashboardData();
    } catch (e) {
      setState(() {
        isLoading = false;
        errorMessage = "Failed to load token: $e";
      });
    }
  }

  Future<void> fetchDashboardData() async {
    if (isGuest) return;

    try {
      setState(() {
        isLoading = true;
        errorMessage = "";
      });

      final response = await http.get(
        ApiConfig.uri("/api/seller/dashboard"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && data["success"] == true) {
        setState(() {
          sellerData = data["seller"];
          summaryData = data["summary"];
          recentProducts = data["recent_products"] ?? [];
          recentOrders = data["recent_orders"] ?? [];
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        final storage = TokenStorage();
        await storage.deleteTokens();

        if (!mounted) return;

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
              (route) => false,
        );
      } else {
        setState(() {
          errorMessage = data["message"] ?? "Failed to load dashboard";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Error: $e";
        isLoading = false;
      });
    }
  }

  Future<void> logoutUser() async {
    final storage = TokenStorage();
    await storage.deleteTokens();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
          (route) => false,
    );
  }

  void guestMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please login first")),
    );
  }

  int _getNewOrdersCount() {
    final value = summaryData?["new_orders"] ??
        summaryData?["today_orders"] ??
        summaryData?["recent_orders_count"];

    if (value is int) return value;
    if (value != null) {
      return int.tryParse(value.toString()) ?? recentOrders.length;
    }
    return recentOrders.length;
  }

  int _getLowStockCount() {
    final value = summaryData?["low_stock_products"] ??
        summaryData?["low_stock_items"] ??
        summaryData?["low_stock_count"];

    if (value is int) return value;
    if (value != null) {
      return int.tryParse(value.toString()) ?? 0;
    }

    int count = 0;
    for (final product in recentProducts) {
      if (product is Map<String, dynamic>) {
        final stockValue =
            product["quantity"] ?? product["stock"] ?? product["product_stock"];
        final stock = int.tryParse((stockValue ?? 0).toString()) ?? 0;
        if (stock <= 5 && stock > 0) {
          count++;
        }
      }
    }
    return count;
  }

  int _getOutOfStockCount() {
    final value = summaryData?["out_of_stock_products"] ??
        summaryData?["out_of_stock_items"] ??
        summaryData?["out_of_stock_count"];

    if (value is int) return value;
    if (value != null) {
      return int.tryParse(value.toString()) ?? 0;
    }

    int count = 0;
    for (final product in recentProducts) {
      if (product is Map<String, dynamic>) {
        final stockValue =
            product["quantity"] ?? product["stock"] ?? product["product_stock"];
        final stock = int.tryParse((stockValue ?? 0).toString()) ?? 0;
        final stockStatus =
        (product["stock_status"] ?? "").toString().toLowerCase();

        if (stock <= 0 || stockStatus == "out of stock") {
          count++;
        }
      }
    }
    return count;
  }

  String _getProfileImageUrl() {
    final seller = sellerData;
    if (seller == null) return "";

    final candidates = [
      seller["store_logo_url"],
      seller["store_logo"],
      seller["profile_image_url"],
      seller["profile_image"],
      seller["image_url"],
      seller["image"],
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? "").toString().trim();
      if (value.isEmpty) continue;

      if (value.startsWith("http://") || value.startsWith("https://")) {
        return value;
      }

      if (value.startsWith("/")) {
        return ApiConfig.fileUrl(value);
      }

      if (value.contains("uploads/")) {
        return ApiConfig.fileUrl("/$value");
      }

      return ApiConfig.fileUrl("/api/seller/logo/$value");
    }

    return "";
  }

  Widget _homeCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFE3F2FD),
                  child: Icon(icon, color: Colors.black),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileImageUrl = _getProfileImageUrl();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2196F3),
        automaticallyImplyLeading: false,
        toolbarHeight: 80,
        title: Row(
          children: [
            InkWell(
              onTap: () async {
                if (isGuest) {
                  guestMessage();
                  return;
                }

                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SellerProfilePage(),
                  ),
                );

                if (result == true) {
                  await fetchDashboardData();
                }
              },
              child: CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                backgroundImage:
                profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
                child: profileImageUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.black)
                    : null,
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    isGuest
                        ? "Welcome Guest "
                        : sellerData != null
                        ? "Welcome ${sellerData!["seller_name"]}"
                        : "Welcome Seller ",
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isGuest
                        ? "Login to manage your shop easily"
                        : sellerData != null
                        ? (sellerData!["shop_name"] ??
                        "Manage your shop easily")
                        : "Manage your shop easily",
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (isGuest)
            TextButton(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => LoginPage()),
                );
              },
              child: const Text(
                "Login",
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            IconButton(
              onPressed: logoutUser,
              icon: const Icon(Icons.logout, color: Colors.black),
            ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(
        child: Text(
          errorMessage,
          style: const TextStyle(color: Colors.red),
        ),
      )
          : RefreshIndicator(
        onRefresh: isGuest ? () async {} : fetchDashboardData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (isGuest)
                Container(
                  width: double.infinity,
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
                  child: const Text(
                    "You are in Guest Mode.\nLogin to access full seller features.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              _homeCard(
                icon: Icons.fiber_new_rounded,
                title: "New Orders",
                subtitle: isGuest
                    ? "Login required"
                    : "${_getNewOrdersCount()} new orders",
                onTap: isGuest
                    ? guestMessage
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OrdersPage(
                        initialSort: "Pending",
                      ),
                    ),
                  );
                },
              ),
              _homeCard(
                icon: Icons.warning_amber_rounded,
                title: "Low Stock Products",
                subtitle: isGuest
                    ? "Login required"
                    : "${_getLowStockCount()} products need refill",
                onTap: isGuest
                    ? guestMessage
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyProductsPage(
                        filterMode: "low_stock",
                      ),
                    ),
                  );
                },
              ),
              _homeCard(
                icon: Icons.remove_shopping_cart_outlined,
                title: "Out of Stock Products",
                subtitle: isGuest
                    ? "Login required"
                    : "${_getOutOfStockCount()} products unavailable",
                onTap: isGuest
                    ? guestMessage
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MyProductsPage(
                        filterMode: "out_of_stock",
                      ),
                    ),
                  );
                },
              ),
              _homeCard(
                icon: Icons.bar_chart_rounded,
                title: "Reports",
                subtitle: isGuest
                    ? "Login required"
                    : "Sales, revenue and most sold products",
                onTap: isGuest
                    ? guestMessage
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SellerReportsPage(),
                    ),
                  );
                },
              ),
              _homeCard(
                icon: Icons.feedback_rounded,
                title: "Feedback",
                subtitle: isGuest
                    ? "Login required"
                    : "View product feedbacks",
                onTap: isGuest
                    ? guestMessage
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SellerFeedbackPage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              if (!isGuest && recentProducts.isNotEmpty)
                _sectionCard(
                  title: "Recent Products",
                  child: Column(
                    children: recentProducts.take(3).map((product) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE3F2FD),
                          child: Icon(
                            Icons.inventory_2_outlined,
                            color: Colors.black,
                          ),
                        ),
                        title: Text(
                          (product["product_name"] ?? "Unnamed Product")
                              .toString(),
                        ),
                        subtitle: Text(
                          "Stock: ${(product["stock_available"] ?? product["stock"] ?? product["quantity"] ?? 0).toString()}",
                        ),
                      );
                    }).toList(),
                  ),
                ),
              if (!isGuest && recentOrders.isNotEmpty)
                _sectionCard(
                  title: "Recent Orders",
                  child: Column(
                    children: recentOrders.take(3).map((order) {
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFFE3F2FD),
                          child: Icon(
                            Icons.receipt_long_outlined,
                            color: Colors.black,
                          ),
                        ),
                        title: Text(
                          (order["order_id"] != null)
                              ? "Order #${order["order_id"]}"
                              : "New Order",
                        ),
                        subtitle: Text(
                          (order["order_status"] ?? "Pending")
                              .toString(),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        selectedItemColor: Colors.black,
        unselectedItemColor: Colors.black54,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF2196F3),
        onTap: (index) {
          if (index == 0) {
            return;
          } else if (index == 1) {
            if (isGuest) {
              guestMessage();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AddProductPage()),
            );
          } else if (index == 2) {
            if (isGuest) {
              guestMessage();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyProductsPage()),
            );
          } else if (index == 3) {
            if (isGuest) {
              guestMessage();
              return;
            }
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OrdersPage()),
            );
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_box_outlined),
            label: "Add Product",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.inventory_2_outlined),
            label: "My Products",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag_outlined),
            label: "Orders",
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}