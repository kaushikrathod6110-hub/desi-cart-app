import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_config.dart';
import '../screens/login_page.dart';
import '../screens/token_storage.dart';

class OrderDetailsPage extends StatefulWidget {
  final Map<String, dynamic> order;

  const OrderDetailsPage({super.key, required this.order});

  @override
  State<OrderDetailsPage> createState() => _OrderDetailsPageState();
}

class _OrderDetailsPageState extends State<OrderDetailsPage> {
  bool isLoading = true;
  String errorMessage = "";
  List<dynamic> orderItems = [];
  Map<String, dynamic>? orderDetails;

  @override
  void initState() {
    super.initState();
    fetchOrderDetails();
  }

  Future<void> fetchOrderDetails() async {
    setState(() {
      isLoading = true;
      errorMessage = "";
    });

    try {
      final orderId = widget.order["order_id"]?.toString() ??
          widget.order["id"]?.toString() ??
          "";

      if (orderId.isEmpty) {
        setState(() {
          errorMessage = "Order ID not found";
          isLoading = false;
        });
        return;
      }

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

      final detailsResponse = await http.get(
        ApiConfig.uri("/api/seller/order-details/$orderId"),
        headers: {
          "Authorization": "Bearer $token",
        },
      );

      final itemsResponse = await http.get(
        ApiConfig.uri("/api/orders/$orderId/products"),
        headers: {
          "Authorization": "Bearer $token",
        },
      );

      final detailsData = detailsResponse.body.isNotEmpty
          ? jsonDecode(detailsResponse.body)
          : {};
      final itemsData = itemsResponse.body.isNotEmpty
          ? jsonDecode(itemsResponse.body)
          : {};

      if (detailsResponse.statusCode == 200 && detailsData["success"] == true) {
        setState(() {
          orderDetails = detailsData["order"] is Map<String, dynamic>
              ? Map<String, dynamic>.from(detailsData["order"])
              : null;
          orderItems = itemsData["products"] ??
              itemsData["items"] ??
              itemsData["order_items"] ??
              [];
          isLoading = false;
        });
      } else if (detailsResponse.statusCode == 401 ||
          detailsResponse.statusCode == 422 ||
          itemsResponse.statusCode == 401 ||
          itemsResponse.statusCode == 422) {
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      } else {
        setState(() {
          errorMessage = detailsData["message"] ?? "Failed to load order details";
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

  String _readValue(List<String> keys, {String fallback = ""}) {
    for (final key in keys) {
      final detailValue = orderDetails?[key];
      if (detailValue != null && detailValue.toString().trim().isNotEmpty) {
        return detailValue.toString();
      }

      final widgetValue = widget.order[key];
      if (widgetValue != null && widgetValue.toString().trim().isNotEmpty) {
        return widgetValue.toString();
      }
    }
    return fallback;
  }

  String _getStatus() {
    return _readValue(["status", "order_status"]);
  }

  String _getCustomer() {
    return _readValue(
      ["customer_name", "user_name", "customer"],
      fallback: widget.order["user_id"] != null
          ? "User #${widget.order["user_id"]}"
          : "Customer",
    );
  }

  String _getCustomerEmail() {
    return _readValue(["user_email", "customer_email"]);
  }

  String _getCustomerMobile() {
    return _readValue(["user_mobile", "customer_mobile"]);
  }

  String _getDate() {
    return _readValue(["date", "order_date"]);
  }

  String _getAmount() {
    return _readValue(["amount", "total_amount"], fallback: "0");
  }

  String _getPaymentMethod() {
    return _readValue(["payment_method"]);
  }

  String _getPaymentStatus() {
    return _readValue(["payment_status", "payment"]);
  }

  String _getDeliveryStatus() {
    return _readValue(["delivery_status"]);
  }

  String _getAddress() {
    final address = _readValue(["delivery_address"]);
    final pincode = _readValue(["pincode"]);

    if (address.isEmpty) return pincode;
    if (pincode.isEmpty) return address;
    return "$address - $pincode";
  }

  String _getNotes() {
    return _readValue(["notes"]);
  }

  String _getOrderIdText() {
    return (widget.order["orderId"] ??
        orderDetails?["orderId"] ??
        "#ORD${widget.order["order_id"] ?? ""}")
        .toString();
  }

  int _getItemQuantity(dynamic item) {
    return int.tryParse(
      (item["quantity"] ?? item["qty"] ?? item["ordered_qty"] ?? 1)
          .toString(),
    ) ??
        1;
  }

  double _getItemPrice(dynamic item) {
    return double.tryParse(
      (item["price"] ??
          item["unit_price"] ??
          item["amount"] ??
          item["ordered_price"] ??
          0)
          .toString(),
    ) ??
        0;
  }

  double _getItemsTotal() {
    double total = 0;
    for (final item in orderItems) {
      total += _getItemPrice(item) * _getItemQuantity(item);
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Order Details",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF2196F3),
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryCard(),
            const SizedBox(height: 16),
            _customerCard(),
            const SizedBox(height: 16),
            _deliveryCard(),
            const SizedBox(height: 16),
            _itemsCard(),
            const SizedBox(height: 16),
            _totalCard(),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Order Summary",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _getOrderIdText(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(_getStatus()),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _infoTile(Icons.calendar_today_outlined, "Order Date", _getDate()),
              _infoTile(Icons.payments_outlined, "Payment Method", _getPaymentMethod()),
              _infoTile(Icons.verified_outlined, "Payment Status", _getPaymentStatus()),
              _infoTile(Icons.local_shipping_outlined, "Delivery Status", _getDeliveryStatus()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _customerCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Customer Details",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _detailRow(Icons.person_outline, "Customer Name", _getCustomer()),
          _detailRow(
            Icons.email_outlined,
            "Email",
            _getCustomerEmail().isEmpty ? "Not available" : _getCustomerEmail(),
          ),
          _detailRow(
            Icons.phone_outlined,
            "Mobile",
            _getCustomerMobile().isEmpty ? "Not available" : _getCustomerMobile(),
          ),
        ],
      ),
    );
  }

  Widget _deliveryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Delivery Details",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          _detailRow(
            Icons.location_on_outlined,
            "Delivery Address",
            _getAddress().isEmpty ? "Not available" : _getAddress(),
          ),
          if (_getNotes().isNotEmpty)
            _detailRow(Icons.sticky_note_2_outlined, "Notes", _getNotes()),
        ],
      ),
    );
  }

  Widget _itemsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Ordered Items",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                "${orderItems.length} item${orderItems.length == 1 ? '' : 's'}",
                style: const TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (orderItems.isEmpty)
            const Text(
              "No items found",
              style: TextStyle(color: Colors.grey),
            )
          else
            ...orderItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              final name = (item["product_name"] ??
                  item["name"] ??
                  item["title"] ??
                  "Product")
                  .toString();

              final qty = _getItemQuantity(item);
              final price = _getItemPrice(item);

              return Column(
                children: [
                  _itemRow(name, qty, price),
                  if (index != orderItems.length - 1)
                    const Divider(height: 18, thickness: 0.8),
                ],
              );
            }).toList(),
        ],
      ),
    );
  }

  Widget _totalCard() {
    final backendAmount = double.tryParse(_getAmount()) ?? 0;
    final itemsTotal = _getItemsTotal();
    final displayTotal = backendAmount > 0 ? backendAmount : itemsTotal;

    return _card(
      child: Column(
        children: [
          _amountRow("Items Total", itemsTotal),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          _amountRow(
            "Grand Total",
            displayTotal,
            isBold: true,
          ),
        ],
      ),
    );
  }

  Widget _amountRow(String label, double amount, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        Text(
          "₹${amount.toStringAsFixed(0)}",
          style: TextStyle(
            fontSize: isBold ? 18 : 15,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
            color: isBold ? Colors.purple : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? "Not available" : value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.blueAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _itemRow(String name, int qty, double price) {
    final total = price * qty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.shopping_bag_outlined,
            size: 20,
            color: Colors.blueAccent,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Qty: $qty × ₹${price.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          "₹${total.toStringAsFixed(0)}",
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case "Pending":
        color = Colors.orange;
        break;
      case "Accepted":
      case "Confirmed":
        color = Colors.blue;
        break;
      case "Packed":
        color = Colors.deepPurple;
        break;
      case "OutForDelivery":
      case "Out for Delivery":
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
        status.isEmpty ? "Unknown" : status,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}