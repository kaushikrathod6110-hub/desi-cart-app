import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_app/seller/my_products_page.dart';
import 'package:my_app/user/user_home_page.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:my_app/user/user_my_orders_page.dart';
import 'package:my_app/user/user_product_page.dart';

import '../api_config.dart';
import 'package:my_app/screens/token_storage.dart';

class PaymentPage extends StatefulWidget {
  final double totalAmount;
  final String address;
  final String pincode;
  final Map<String, dynamic>? singleItem;

  const PaymentPage({
    super.key,
    required this.totalAmount,
    required this.address,
    required this.pincode,
    this.singleItem,
  });

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  late Razorpay _razorpay;
  String orderId = "";
  int selectedMethod = 1;
  String razorpayKeyId = "";
  bool isProcessing = false;
  List<int> currentOrderIds = [];
  Map<String, dynamic> currentOrderAmounts = {};

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();

    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handleSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handleError);
  }

  // WEB FIX
  void startWebPayment() async {
    final url = Uri.parse("https://rzp.io/l/your_link_here");

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  List<int> _extractOrderIds(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => int.tryParse(e.toString()))
        .whereType<int>()
        .toList();
  }

  Map<String, dynamic> _extractOrderAmounts(dynamic raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return {};
  }

  double _amountForOrder(int orderId) {
    final dynamic value = currentOrderAmounts[orderId.toString()];
    if (value == null) return widget.totalAmount;
    return double.tryParse(value.toString()) ?? widget.totalAmount;
  }

  Future<void> _recordPaymentForCurrentOrders({
    required String paymentMethod,
    required String paymentStatus,
    String? transactionId,
  }) async {
    if (currentOrderIds.isEmpty) return;

    for (final int id in currentOrderIds) {
      await http.post(
        ApiConfig.uri("/api/payment/record"),
        headers: await getHeaders(),
        body: jsonEncode({
          "order_id": id,
          "transaction_id": transactionId,
          "payment_method": paymentMethod,
          "payment_status": paymentStatus,
          "amount": _amountForOrder(id),
        }),
      );
    }
  }

  // ORDER SAVE
  Future<Map<String, dynamic>?> placeOrder(String method, {String? paymentStatus}) async {
    try {
      final res = await http.post(
        ApiConfig.uri("/place_order"),
        headers: await getHeaders(),
        body: jsonEncode({
          "payment_method": method == "Razorpay" ? "Online" : "COD",
          if (paymentStatus != null) "payment_status": paymentStatus,
          "address": widget.address,
          "pincode": widget.pincode,
          if (widget.singleItem != null) "single_item": widget.singleItem,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["status"] == "success") {
        return Map<String, dynamic>.from(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data["message"]?.toString() ?? "Order place failed",
            ),
          ),
        );
      }

      return null;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Order error: $e")),
        );
      }
      return null;
    }
  }

  Future<void> createOrder() async {
    if (isProcessing) return;

    try {
      if (mounted) {
        setState(() => isProcessing = true);
      }

      currentOrderIds = [];
      currentOrderAmounts = {};

      final response = await http.post(
        ApiConfig.uri("/create_order"),
        headers: await getHeaders(),
        body: jsonEncode({"amount": (widget.totalAmount * 100).toInt()}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200 ||
          data["status"] != "success" ||
          data["order"] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                data["message"]?.toString() ?? "Unable to create Razorpay order",
              ),
            ),
          );
          setState(() => isProcessing = false);
        }
        return;
      }

      final order = data["order"];
      orderId = order["id"];
      razorpayKeyId = (data["key_id"] ?? "").toString();

      if (razorpayKeyId.isEmpty || orderId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Invalid Razorpay response")),
          );
          setState(() => isProcessing = false);
        }
        return;
      }

      openCheckout({...order, "key_id": razorpayKeyId});
    } catch (e) {
      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Razorpay error: $e")),
        );
      }
    }
  }

  void openCheckout(data) {
    var options = {
      'key': data['key_id'],
      'amount': data["amount"],
      'order_id': data["id"],
      'name': 'Shopping App',
      'description': 'Order Payment',
    };

    _razorpay.open(options);
  }

  void _handleSuccess(PaymentSuccessResponse response) async {
    try {
      if (mounted) {
        setState(() => isProcessing = true);
      }

      final verifyRes = await http.post(
        ApiConfig.uri("/verify_payment"),
        headers: await getHeaders(),
        body: jsonEncode({
          "order_id": orderId,
          "payment_id": response.paymentId,
          "signature": response.signature
        }),
      );

      final verifyData = jsonDecode(verifyRes.body);

      if (verifyRes.statusCode != 200 || verifyData["status"] != "success") {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Payment verification failed")),
          );
          setState(() => isProcessing = false);
        }
        return;
      }

      final placedOrderData = await placeOrder("Razorpay", paymentStatus: "Paid");
      if (placedOrderData == null) {
        if (mounted) {
          setState(() => isProcessing = false);
        }
        return;
      }

      currentOrderIds = _extractOrderIds(placedOrderData["order_ids"]);
      currentOrderAmounts = _extractOrderAmounts(placedOrderData["order_amounts"]);

      await _recordPaymentForCurrentOrders(
        paymentMethod: "Online",
        paymentStatus: "Success",
        transactionId: response.paymentId,
      );

      if (!mounted) return;
      setState(() => isProcessing = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SuccessScreen()),
      );
    } catch (e) {
      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment success handling error: $e")),
        );
      }
    }
  }

  void _handleError(PaymentFailureResponse response) async {
    if (mounted) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            response.message?.isNotEmpty == true
                ? "Payment Failed: ${response.message}"
                : "Payment Failed",
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  // UI SAME (NO CHANGE)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payments"),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // STEP UI SAME
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
                    Text("Address")
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(radius: 12, child: Text("2")),
                    SizedBox(height: 4),
                    Text("Order Summary")
                  ],
                ),
                Column(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.blue,
                      child: Text("3"),
                    ),
                    SizedBox(height: 4),
                    Text("Payment")
                  ],
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Total Amount"),
                Text(
                  "₹${widget.totalAmount.toInt()}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )
              ],
            ),
          ),

          Expanded(
            child: ListView(
              children: [
                ExpansionTile(
                  title: const Text("UPI"),
                  children: [
                    RadioListTile(
                      value: 3,
                      groupValue: selectedMethod,
                      onChanged: (v) =>
                          setState(() => selectedMethod = v as int),
                      title: const Text("Razorpay"),
                    ),
                  ],
                ),
                ExpansionTile(
                  title: const Text("Cash on Delivery"),
                  children: [
                    RadioListTile(
                      value: 4,
                      groupValue: selectedMethod,
                      onChanged: (v) =>
                          setState(() => selectedMethod = v as int),
                      title: const Text("Pay after delivery"),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(10),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                minimumSize: const Size(double.infinity, 50),
              ),
              onPressed: isProcessing
                  ? null
                  : () async {
                if (selectedMethod == 4) {
                  setState(() => isProcessing = true);

                  final orderData = await placeOrder("COD", paymentStatus: "Pending");

                  if (!mounted) return;

                  if (orderData != null) {
                    currentOrderIds = _extractOrderIds(orderData["order_ids"]);
                    currentOrderAmounts = _extractOrderAmounts(orderData["order_amounts"]);
                    await _recordPaymentForCurrentOrders(
                      paymentMethod: "COD",
                      paymentStatus: "Pending",
                    );
                  }

                  setState(() => isProcessing = false);

                  if (orderData != null) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SuccessScreen(),
                      ),
                    );
                  }
                  return;
                }

                if (selectedMethod == 3) {
                  await createOrder();
                }
              },
              child: Text(
                isProcessing
                    ? "Processing..."
                    : "Pay ₹${widget.totalAmount.toInt()}",
              ),
            ),
          )
        ],
      ),
    );
  }
}

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xfff3edf7),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 100),
                const SizedBox(height: 20),
                const Text(
                  "Order Placed Successfully",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  "Your order has been placed successfully.",
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const UserMyOrdersPage()),
                            (route) => false,
                      );
                    },
                    child: const Text("Go to My Orders"),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const HomePage()),
                            (route) => false,
                      );
                    },
                    child: const Text("Continue Shopping"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}