import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_product_detail_page.dart';
import '../delivery_staff/delivery_staff_rating_page.dart';

class UserOrderDetailsPage extends StatefulWidget {
  final int orderId;

  const UserOrderDetailsPage({super.key, required this.orderId});

  @override
  State<UserOrderDetailsPage> createState() => _UserOrderDetailsPageState();
}

class _UserOrderDetailsPageState extends State<UserOrderDetailsPage> {
  bool isLoading = true;
  bool isCancelling = false;
  bool isDeliveryReviewLoading = false;
  Timer? _ticker;
  DateTime nowTime = DateTime.now();
  Map<String, dynamic>? order;
  Map<String, dynamic>? deliveryReviewData;

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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => nowTime = DateTime.now());
    });
    fetchOrderDetails();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> fetchOrderDetails() async {
    setState(() => isLoading = true);

    try {
      final res = await http.get(
        ApiConfig.uri("/api/user/orders/${widget.orderId}"),
        headers: await getHeaders(),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["success"] == true) {
        final loadedOrder = Map<String, dynamic>.from(data["order"]);
        setState(() {
          order = loadedOrder;
          isLoading = false;
        });
        await fetchDeliveryReviewState();
      } else {
        setState(() => isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data["message"]?.toString() ?? "Failed to load order")),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Order details error: $e")),
      );
    }
  }

  Future<void> cancelOrder() async {
    setState(() => isCancelling = true);

    try {
      final res = await http.put(
        ApiConfig.uri("/api/user/orders/${widget.orderId}/cancel"),
        headers: await getHeaders(),
      );

      final data = jsonDecode(res.body);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data["message"]?.toString() ?? "Response received")),
      );

      if (res.statusCode == 200 && data["success"] == true) {
        await fetchOrderDetails();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Cancel error: $e")),
      );
    }

    if (mounted) {
      setState(() => isCancelling = false);
    }
  }


  int remainingCancelSeconds() {
    final direct = int.tryParse((order?['cancel_window_remaining_seconds'] ?? '').toString());
    if (direct != null) {
      final orderDate = (order?['order_date'] ?? '').toString();
      try {
        final parsed = DateTime.parse(orderDate).toLocal();
        final end = parsed.add(const Duration(minutes: 5));
        final diff = end.difference(nowTime).inSeconds;
        return diff > 0 ? diff : 0;
      } catch (_) {
        return direct > 0 ? direct : 0;
      }
    }
    final raw = (order?['order_date'] ?? '').toString();
    try {
      final parsed = DateTime.parse(raw).toLocal();
      final end = parsed.add(const Duration(minutes: 5));
      final diff = end.difference(nowTime).inSeconds;
      return diff > 0 ? diff : 0;
    } catch (_) {
      return 0;
    }
  }

  String formatRemaining(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case "delivered":
        return Colors.green;
      case "cancelled":
        return Colors.red;
      case "pending":
        return Colors.orange;
      case "confirmed":
      case "packed":
      case "outfordelivery":
      case "out for delivery":
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget infoTile(String label, String value, {IconData? icon}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.blue, size: 20),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? "-" : value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget statusChip(String text, Color color, {bool filled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.12) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? color : Colors.black87,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }



  bool get canOpenDeliveryRating {
    final orderStatus = (order?["order_status"] ?? "").toString().toLowerCase();
    final deliveryStatus = (order?["delivery_status"] ?? "").toString().toLowerCase();
    final deliveryStaffId = int.tryParse((order?["delivery_staff_id"] ?? '').toString());
    final skipped = deliveryReviewData?["is_skipped"] == true;
    return deliveryStaffId != null &&
        deliveryStaffId > 0 &&
        (orderStatus == 'delivered' || deliveryStatus == 'delivered') &&
        !skipped;
  }

  Future<void> fetchDeliveryReviewState() async {
    final deliveryStaffId = int.tryParse((order?["delivery_staff_id"] ?? '').toString());
    final orderStatus = (order?["order_status"] ?? "").toString().toLowerCase();
    final deliveryStatus = (order?["delivery_status"] ?? "").toString().toLowerCase();

    if (deliveryStaffId == null || deliveryStaffId <= 0 || (orderStatus != 'delivered' && deliveryStatus != 'delivered')) {
      if (mounted) {
        setState(() {
          deliveryReviewData = null;
          isDeliveryReviewLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => isDeliveryReviewLoading = true);
    try {
      final res = await http.get(
        ApiConfig.uri('/api/delivery-staff/reviews/order/${widget.orderId}'),
        headers: await getHeaders(),
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          deliveryReviewData = Map<String, dynamic>.from(jsonDecode(res.body));
          isDeliveryReviewLoading = false;
        });
      } else {
        setState(() {
          deliveryReviewData = null;
          isDeliveryReviewLoading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        deliveryReviewData = null;
        isDeliveryReviewLoading = false;
      });
    }
  }

  Future<void> openDeliveryRatingPage() async {
    final deliveryStaffId = int.tryParse((order?["delivery_staff_id"] ?? '').toString());
    if (deliveryStaffId == null || deliveryStaffId <= 0) return;

    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryStaffRatingPage(
          orderId: widget.orderId,
          deliveryStaffId: deliveryStaffId,
          deliveryStaffName: (order?["delivery_staff_name"] ?? '').toString(),
          vehicleType: (order?["vehicle_type"] ?? '').toString(),
        ),
      ),
    );

    if (changed == true) {
      await fetchDeliveryReviewState();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = (order?["items"] as List?) ?? [];
    final canCancel = order?["can_cancel"] == true && remainingCancelSeconds() > 0;
    final remainingSeconds = remainingCancelSeconds();
    final orderStatus = (order?["order_status"] ?? "").toString();
    final rawPaymentStatus = (order?["payment_status"] ?? "").toString();
    final paymentMethod = (order?["payment_method"] ?? "").toString();
    final paymentStatus = orderStatus.toLowerCase() == 'cancelled' && paymentMethod.toLowerCase() == 'online' && rawPaymentStatus.toLowerCase() == 'paid'
        ? 'Refund Initiated'
        : rawPaymentStatus;

    return Scaffold(
      backgroundColor: const Color(0xfff6f3fb),
      appBar: AppBar(
        title: Text("Order #${widget.orderId}"),
        backgroundColor: Colors.blue,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : order == null
          ? const Center(child: Text("Order not found"))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      statusChip(orderStatus, statusColor(orderStatus)),
                      statusChip("Payment: $paymentStatus", Colors.grey, filled: false),
                      if (canCancel) statusChip("Cancel in ${formatRemaining(remainingSeconds)}", Colors.red),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    "₹${(order?["total_amount"] ?? 0).toString()}",
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Payment Method: ${order?["payment_method"] ?? "-"}",
                    style: TextStyle(color: Colors.grey.shade800, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Delivery Status: ${order?["delivery_status"] ?? "-"}",
                    style: TextStyle(color: Colors.grey.shade800, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            infoTile(
              "Delivery Address",
              (order?["delivery_address"] ?? "").toString(),
              icon: Icons.location_on_outlined,
            ),
            infoTile(
              "Pincode",
              (order?["pincode"] ?? "").toString(),
              icon: Icons.pin_drop_outlined,
            ),
            infoTile(
              "Seller",
              (order?["shop_name"] ?? order?["seller_name"] ?? "").toString(),
              icon: Icons.storefront_outlined,
            ),
            infoTile(
              "Seller Mobile",
              (order?["seller_mobile"] ?? "").toString(),
              icon: Icons.phone_outlined,
            ),
            const SizedBox(height: 8),
            const Text(
              "Items",
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            ...items.map((e) {
              final item = Map<String, dynamic>.from(e);
              final image = (item["prod_image_url"] ?? "").toString();

              final prodId = item["prod_id"];

              return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: prodId == null
                      ? null
                      : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ProductDetailPage(
                          prodId: int.tryParse((prodId ?? 0).toString()) ?? 0,
                          sellerId: int.tryParse(((item["seller_id"] ?? order?["seller_id"] ?? 0)).toString()),
                          initialProduct: {
                            'prod_id': int.tryParse((prodId ?? 0).toString()) ?? 0,
                            'seller_id': int.tryParse(((item["seller_id"] ?? order?["seller_id"] ?? 0)).toString()) ?? 0,
                            'prod_name': (item["prod_name"] ?? '').toString(),
                            'prod_image': (item["prod_image_url"] ?? item["prod_image"] ?? '').toString(),
                            'prod_price': item["price"] ?? 0,
                            'description': (item["description"] ?? '').toString(),
                            'seller_name': (order?["shop_name"] ?? order?["seller_name"] ?? '').toString(),
                            'stock_quantity': item["stock_quantity"] ?? item["available_stock"] ?? 0,
                            'stock_status': (item["stock_status"] ?? 'Available').toString(),
                          },
                          wishlist: const [],
                          onUpdate: () {},
                        ),
                      ),
                    );
                    await fetchOrderDetails();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 78,
                          height: 78,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: image.isNotEmpty
                                ? Image.network(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.image_not_supported,
                                color: Colors.grey,
                              ),
                            )
                                : const Icon(
                              Icons.shopping_bag_outlined,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item["prod_name"] ?? "").toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Qty: ${item["quantity"] ?? 1}",
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Price: ₹${item["price"] ?? 0}",
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                              if ((item["description"] ?? "").toString().trim().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  (item["description"] ?? "").toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ));
            }).toList(),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade800, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No Return Policy: This order will not be returned after the producers deliver it..',
                      style: TextStyle(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (canCancel)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.withOpacity(0.18)),
                ),
                child: Text(
                  'You can cancel this order for the next ${formatRemaining(remainingSeconds)}.',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Order cancellation is available only within 5 minutes after placing the order.',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            if (isDeliveryReviewLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: 14),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (canOpenDeliveryRating)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: openDeliveryRatingPage,
                  child: Text(
                    deliveryReviewData?["has_review"] == true ? "Edit Delivery Rating" : "Rate Delivery",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            if (canCancel)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: isCancelling ? null : cancelOrder,
                  child: Text(
                    isCancelling ? "Cancelling..." : "Cancel Order",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}