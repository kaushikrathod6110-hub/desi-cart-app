import 'user_auth_session.dart';
import "package:my_app/api_config.dart";
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/user/user_payment_page.dart';
import 'package:my_app/screens/token_storage.dart';

class OrderSummaryPage extends StatefulWidget {
  final Map<String, dynamic>? singleItem;

  const OrderSummaryPage({
    super.key,
    this.singleItem,
  });

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  @override
  State<OrderSummaryPage> createState() => _OrderSummaryPageState();
}

class _OrderSummaryPageState extends State<OrderSummaryPage> {
  int? userId;
  List items = [];
  Map<String, dynamic>? user;
  bool isLoading = true;
  double total = 0;
  static const double platformFee = 7;
  static const double deliveryStaffFee = 20;
  Map<String, dynamic>? selectedAddress;

  bool isItemOutOfStock(dynamic item) {
    if (item is! Map) return false;
    final stockStatus = (item["stock_status"] ?? '').toString().toLowerCase().trim();
    final stockQty = double.tryParse((item["stock_quantity"] ?? 0).toString()) ?? 0;
    return stockStatus == 'out of stock' || stockQty <= 0;
  }

  bool get hasOutOfStockItems => items.any(isItemOutOfStock);

  Future<void> fetchData() async {
    if (widget.singleItem != null) {
      items = [widget.singleItem!];
      final qty = int.tryParse(widget.singleItem!["quantity"].toString()) ?? 1;
      final price = double.tryParse(widget.singleItem!["prod_price"].toString()) ?? 0;
      total = (price * qty) + platformFee + deliveryStaffFee;

      final res = await http.get(
        ApiConfig.uri("/order_summary/${userId ?? 0}"),
        headers: await widget.getHeaders(),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        user = Map<String, dynamic>.from(data["user"] ?? {});
        selectedAddress = user;
      }

      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      return;
    }

    final res = await http.get(
      ApiConfig.uri("/order_summary/${userId ?? 0}"),
      headers: await widget.getHeaders(),
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final fetchedItems = (data["items"] as List? ?? []);
      final fetchedUser = Map<String, dynamic>.from(data["user"] ?? {});

      final itemsTotal = fetchedItems.fold<double>(
        0,
            (sum, e) => sum + ((double.tryParse((e["prod_price"] ?? 0).toString()) ?? 0) * (int.tryParse((e["quantity"] ?? 1).toString()) ?? 1)),
      );

      setState(() {
        items = fetchedItems;
        user = fetchedUser;
        selectedAddress = fetchedUser;
        total = itemsTotal + (fetchedItems.isEmpty ? 0 : (platformFee + deliveryStaffFee));
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  String getImage(String img) {
    final raw = img.trim();
    if (raw.isEmpty) return '';
    if (raw.contains(",")) {
      final first = raw.split(",").first.trim();
      if (first.startsWith("http")) return first;
      return ApiConfig.fileUrl(first);
    }
    if (raw.startsWith("http")) {
      return raw;
    }
    return ApiConfig.fileUrl(raw);
  }

  void openAddressPopup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        final name = TextEditingController();
        final address = TextEditingController();
        final pincode = TextEditingController();

        return AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(15),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Select delivery address",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: name, decoration: const InputDecoration(labelText: "Name")),
                  TextField(controller: address, decoration: const InputDecoration(labelText: "Address")),
                  TextField(controller: pincode, decoration: const InputDecoration(labelText: "Pincode")),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedAddress = {
                          "user_name": name.text.isNotEmpty ? name.text : (selectedAddress?["user_name"] ?? ''),
                          "user_address": address.text.isNotEmpty ? address.text : (selectedAddress?["user_address"] ?? ''),
                          "pincode": pincode.text.isNotEmpty ? pincode.text : (selectedAddress?["pincode"] ?? ''),
                        };
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("Add / Select"),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    userId = await UserAuthSession.getCurrentUserId();
    if (userId != null) {
      await fetchData();
    } else if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Widget _buildItemCard(Map item) {
    final imageUrl = getImage((item["prod_image"] ?? '').toString());
    final outOfStock = isItemOutOfStock(item);

    return Card(
      margin: const EdgeInsets.all(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            imageUrl.isEmpty
                ? Container(
              width: 70,
              height: 70,
              color: Colors.grey.shade100,
              alignment: Alignment.center,
              child: const Icon(Icons.image_outlined, color: Colors.grey),
            )
                : Image.network(
              imageUrl,
              width: 70,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 70,
                height: 70,
                color: Colors.grey.shade100,
                alignment: Alignment.center,
                child: const Icon(Icons.image_outlined, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (item["prod_name"] ?? '').toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text("Seller: ${(item["seller_name"] ?? '').toString()}"),
                  Text("₹ ${(item["prod_price"] ?? 0).toString()}"),
                  Text("Qty: ${(item["quantity"] ?? 1).toString()}"),
                  const SizedBox(height: 4),
                  Text(
                    outOfStock ? 'Out of Stock' : 'Available',
                    style: TextStyle(
                      color: outOfStock ? Colors.red : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Order Summary"),
        backgroundColor: Colors.blue,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                Column(
                  children: [
                    CircleAvatar(radius: 12, child: Text("1")),
                    SizedBox(height: 4),
                    Text("Address"),
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(radius: 12, backgroundColor: Colors.blue, child: Text("2")),
                    SizedBox(height: 4),
                    Text("Order Summary"),
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(radius: 12, child: Text("3")),
                    SizedBox(height: 4),
                    Text("Payment"),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Deliver to:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    TextButton(
                      onPressed: openAddressPopup,
                      child: const Text("Change"),
                    ),
                  ],
                ),
                Text("${selectedAddress?["user_name"] ?? ''}"),
                Text("${selectedAddress?["user_address"] ?? ''}"),
                Text("${selectedAddress?["pincode"] ?? ''}"),
              ],
            ),
          ),
          const Divider(),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade800, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No Return Policy: If you are placing an order than you agree that these products are not returnable.',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasOutOfStockItems)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Text(
                'Some products are out of stock. You can continue only when all products become available.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _buildItemCard(Map<String, dynamic>.from(items[index])),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Items Total"),
                    Text("₹ ${(total - (items.isEmpty ? 0 : (platformFee + deliveryStaffFee))).toStringAsFixed(0)}"),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text("Platform Fee"),
                    Text("₹ 7"),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text("Delivery Staff Fee"),
                    Text("₹ 20"),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "₹ ${total.toStringAsFixed(0)}",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasOutOfStockItems ? Colors.grey : Colors.orange,
                  ),
                  onPressed: () {
                    if (selectedAddress == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please select address")),
                      );
                      return;
                    }

                    if (hasOutOfStockItems) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Some products are out of stock. Please remove them or wait until available."),
                        ),
                      );
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PaymentPage(
                          totalAmount: total,
                          address: selectedAddress!["user_address"].toString(),
                          pincode: selectedAddress!["pincode"].toString(),
                          singleItem: widget.singleItem,
                        ),
                      ),
                    );
                  },
                  child: Text(hasOutOfStockItems ? "Unavailable items in order" : "Continue"),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}