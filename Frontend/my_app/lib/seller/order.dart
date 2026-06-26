import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../screens/login_page.dart';
import '../screens/token_storage.dart';
import 'order_details_page.dart';


class OrdersPage extends StatefulWidget {
  final String? initialSort;

  const OrdersPage({super.key, this.initialSort});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final TextEditingController searchController = TextEditingController();

  String searchText = "";
  String selectedSort = "Date";
  bool isLoading = true;
  String errorMessage = "";

  List<Map<String, dynamic>> orders = [];

  @override
  void initState() {
    super.initState();
    selectedSort = widget.initialSort ?? "Date";
    fetchOrders();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchOrders() async {
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

      final uri = ApiConfig.uri(
        "/api/seller/orders",
        queryParameters: {
          "search": searchText,
          "sort": selectedSort,
        },
      );

      final response = await http.get(
        uri,
        headers: {
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["success"] == true) {
          final List<dynamic> ordersData = data["orders"];

          setState(() {
            orders = ordersData.map<Map<String, dynamic>>((order) {
              return {
                "order_id": order["order_id"],
                "seller_id": order["seller_id"],
                "cart_id": order["cart_id"],
                "user_id": order["user_id"],
                "delivery_staff_id": order["delivery_staff_id"],
                "order_date": order["order_date"],
                "total_amount": order["total_amount"],
                "payment_method": order["payment_method"],
                "payment_status": order["payment_status"],
                "order_status": order["order_status"],
                "delivery_status": order["delivery_status"],
                "delivery_address": order["delivery_address"],
                "pincode": order["pincode"],
                "notes": order["notes"],

                // UI fields
                "orderId": order["orderId"] ?? "#ORD${order["order_id"]}",
                "customer": order["customer"] ?? "Cart #${order["cart_id"]}",
                "date": order["date"] ?? "",
                "time": order["time"] ?? "",
                "amount": order["amount"] ?? 0,
                "status": order["status"] ?? "",
                "payment": order["payment"] ?? "",
              };
            }).toList();
          });
        } else {
          setState(() {
            errorMessage = data["message"] ?? "Failed to load orders";
          });
        }
      } else if (response.statusCode == 401 || response.statusCode == 422) {
        final storage = TokenStorage();
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      } else {
        setState(() {
          errorMessage = "Server error: ${response.statusCode}";
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Error: $e";
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getFilteredAndSortedOrders() {
    List<Map<String, dynamic>> filteredOrders = List<Map<String, dynamic>>.from(
      orders.where((order) {
        final query = searchText.toLowerCase().trim();
        if (query.isEmpty) return true;

        return order["orderId"].toString().toLowerCase().contains(query) ||
            order["customer"].toString().toLowerCase().contains(query) ||
            order["status"].toString().toLowerCase().contains(query) ||
            order["payment"].toString().toLowerCase().contains(query) ||
            order["date"].toString().toLowerCase().contains(query) ||
            order["time"].toString().toLowerCase().contains(query) ||
            order["delivery_address"].toString().toLowerCase().contains(query) ||
            order["payment_method"].toString().toLowerCase().contains(query) ||
            order["notes"].toString().toLowerCase().contains(query);
      }),
    );

    switch (selectedSort) {
      case "Pending":
        filteredOrders = filteredOrders
            .where((order) => order["status"].toString().trim().toLowerCase() == "pending")
            .toList();
        break;

      case "Accepted":
        filteredOrders = filteredOrders
            .where((order) {
          final status = order["status"].toString().trim().toLowerCase();
          return status == "confirmed" || status == "accepted";
        })
            .toList();
        break;

      case "Delivered":
        filteredOrders = filteredOrders
            .where((order) => order["status"].toString().trim().toLowerCase() == "delivered")
            .toList();
        break;

      case "Failed":
        filteredOrders = filteredOrders
            .where((order) {
          final status = order["status"].toString().trim().toLowerCase();
          final payment = order["payment"].toString().trim().toLowerCase();
          return status == "failed" || payment == "failed";
        })
            .toList();
        break;

      case "Customized":
        filteredOrders.sort(
              (a, b) => a["customer"].toString().toLowerCase().compareTo(
            b["customer"].toString().toLowerCase(),
          ),
        );
        return filteredOrders;

      case "Time":
        filteredOrders.sort(
              (a, b) => b["order_date"].toString().compareTo(a["order_date"].toString()),
        );
        return filteredOrders;

      case "Date":
      default:
        filteredOrders.sort(
              (a, b) => b["order_date"].toString().compareTo(a["order_date"].toString()),
        );
        return filteredOrders;
    }

    filteredOrders.sort(
          (a, b) => b["order_date"].toString().compareTo(a["order_date"].toString()),
    );
    return filteredOrders;
  }

  String _getEmptyMessage() {
    switch (selectedSort) {
      case "Pending":
        return "No pending orders found";
      case "Accepted":
        return "No accepted orders found";
      case "Delivered":
        return "No delivered orders found";
      case "Failed":
        return "No failed orders found";
      case "Time":
        return "No orders found for the selected time filter";
      case "Date":
        return "No orders found for the selected date filter";
      default:
        return "No orders found";
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredOrders = _getFilteredAndSortedOrders();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "My Orders",
          style: TextStyle(
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
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) {
                      setState(() {
                        searchText = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: "Search orders.",
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
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedSort,
                      icon: const Icon(
                        Icons.filter_list,
                        color: Colors.blueAccent,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      items: const [
                        DropdownMenuItem(value: "Date", child: Text("Date")),
                        DropdownMenuItem(value: "Time", child: Text("Time")),
                        DropdownMenuItem(
                          value: "Accepted",
                          child: Text("Accepted"),
                        ),
                        DropdownMenuItem(
                          value: "Delivered",
                          child: Text("Delivered"),
                        ),
                        DropdownMenuItem(
                          value: "Pending",
                          child: Text("Pending"),
                        ),
                        DropdownMenuItem(
                          value: "Failed",
                          child: Text("Failed"),
                        ),
                        DropdownMenuItem(
                          value: "Customized",
                          child: Text("Customized"),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            selectedSort = value;
                          });
                          fetchOrders();
                        }
                      },
                    ),
                  ),
                ),
              ],
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
                : filteredOrders.isEmpty
                ? Center(
              child: Text(
                _getEmptyMessage(),
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredOrders.length,
              itemBuilder: (context, index) {
                final order = filteredOrders[index];

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order["orderId"],
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          _statusChip(order["status"]),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Customer: ${order["customer"]}",
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Date: ${order["date"]}",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "Time: ${order["time"]}",
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "₹${order["amount"]}",
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => OrderDetailsPage(
                                    order: order,
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              "View Details",
                              style: TextStyle(
                                color: Colors.purple,
                              ),
                            ),
                          ),
                        ],
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

  Widget _statusChip(String status) {
    Color color;

    switch (status) {
      case "Pending":
        color = Colors.orange;
        break;
      case "Confirmed":
        color = Colors.blue;
        break;
      case "Packed":
        color = Colors.deepPurple;
        break;
      case "OutForDelivery":
        color = Colors.teal;
        break;
      case "Delivered":
        color = Colors.green;
        break;
      case "Cancelled":
      case "Failed":
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}