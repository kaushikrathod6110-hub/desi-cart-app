import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/screens/token_storage.dart';
import 'dart:convert';

Color deliveryStatusColor(String status) {
  switch (status.toLowerCase()) {
    case 'assigned':
      return Colors.orange;
    case 'picked up':
      return Colors.blue;
    case 'out for delivery':
      return Colors.deepPurple;
    case 'delivered':
      return Colors.green;
    case 'unassigned':
      return Colors.grey;
    default:
      return Colors.black54;
  }
}

String _normalizeDeliveryText(dynamic value) {
  return (value ?? '')
      .toString()
      .trim()
      .toLowerCase()
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

String? _deliveryStageFromOrderStatus(dynamic value) {
  final orderStatus = _normalizeDeliveryText(value);
  switch (orderStatus) {
    case 'pending':
    case 'confirmed':
      return 'Unassigned';
    case 'packed':
      return 'Assigned';
    case 'out for delivery':
      return 'Out For Delivery';
    case 'delivered':
      return 'Delivered';
    default:
      return null;
  }
}

String? _deliveryStageFromDeliveryStatus(dynamic value) {
  final deliveryStatus = _normalizeDeliveryText(value);
  switch (deliveryStatus) {
    case 'unassigned':
      return 'Unassigned';
    case 'assigned':
      return 'Assigned';
    case 'picked up':
      return 'Picked Up';
    case 'out for delivery':
      return 'Out For Delivery';
    case 'delivered':
      return 'Delivered';
    default:
      return null;
  }
}

String effectiveDeliveryStatus(Map<String, dynamic> order) {
  final fromDelivery = _deliveryStageFromDeliveryStatus(order['delivery_status']);
  final fromOrder = _deliveryStageFromOrderStatus(order['order_status']);

  if (fromOrder != null) {
    if (fromDelivery == null || fromDelivery == 'Unassigned') {
      return fromOrder;
    }
    if (fromDelivery == 'Delivered' && fromOrder != 'Delivered') {
      return fromOrder;
    }
    if (fromDelivery == 'Out For Delivery' && fromOrder == 'Assigned') {
      return fromOrder;
    }
  }

  final fallback = fromDelivery ?? fromOrder;
  if (fallback != null) return fallback;

  final rawDelivery = (order['delivery_status'] ?? '').toString().trim();
  if (rawDelivery.isNotEmpty) return rawDelivery;
  return (order['order_status'] ?? '-').toString();
}

String formatMoney(dynamic v) {
  final n = double.tryParse(v.toString()) ?? 0;
  return n.toStringAsFixed(2);
}

String formatDateTimeValue(dynamic v) {
  if (v == null || v.toString().isEmpty) return '-';
  try {
    final d = DateTime.parse(v.toString()).toLocal();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return v.toString();
  }
}

Future<List<Map<String, dynamic>>> fetchSellerProducts(int orderId, int sellerId) async {
  final token = await TokenStorage().getAccessToken();
  final url = ApiConfig.uri('/api/delivery-staff/order/$orderId/seller/$sellerId/items');
  final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

  if (response.statusCode != 200) {
    throw Exception('Failed to load products');
  }

  final data = jsonDecode(response.body);
  final List items = data['items'] ?? [];
  return items.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
}

Widget deliveryStatusChip(String label) {
  final color = deliveryStatusColor(label);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

Widget deliveryDashboardCard({
  required String title,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Container(
    constraints: const BoxConstraints(minHeight: 148),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: LinearGradient(
        colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      border: Border.all(color: color.withOpacity(0.20)),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.08),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: color.withOpacity(0.16),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget deliverySummaryStatCard({
  required String title,
  required String value,
  required Color color,
  IconData icon = Icons.analytics_outlined,
}) {
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: color.withOpacity(0.20)),
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.16),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget deliverySearchField({
  required String hint,
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  required VoidCallback onClear,
}) {
  return TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isNotEmpty ? IconButton(onPressed: onClear, icon: const Icon(Icons.close)) : null,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.black.withOpacity(0.08)),
      ),
    ),
  );
}

Widget deliverySectionTitle(String title, {String? subtitle}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black54)),
      ],
    ],
  );
}

Widget deliverySoftCard({required Widget child, EdgeInsets? padding}) {
  return Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.black.withOpacity(0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

Widget deliveryTimelineTile({
  required String title,
  required String value,
  required IconData icon,
  required Color color,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        radius: 18,
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, size: 18, color: color),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
      ),
    ],
  );
}

Widget deliveryOrderListCard(
    Map<String, dynamic> item, {
      bool showAccept = false,
      bool showOpen = false,
      VoidCallback? onView,
      VoidCallback? onAccept,
    }) {
  final statusLabel = effectiveDeliveryStatus(item);
  final earningAmount = double.tryParse((item['earning_amount'] ?? 0).toString()) ?? 0;

  final List sellersRaw = item['sellers'] ?? [item];
  final Map<String, Map<String, dynamic>> uniqueSellersMap = {};

  for (var s in sellersRaw) {
    final seller = Map<String, dynamic>.from(s as Map);
    final key = '${seller['seller_id'] ?? ''}-${seller['seller_mobile'] ?? ''}';
    uniqueSellersMap.putIfAbsent(key, () => seller);
  }

  final uniqueSellers = uniqueSellersMap.values.where((s) => s['seller_id'] != null && s['seller_id'] != 0).toList();

  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.black.withOpacity(0.05)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: Colors.deepPurple.withOpacity(0.12),
              child: Text(
                '${item['order_id']}',
                style: const TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #${item['order_id']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Rs. ${formatMoney(item['total_amount'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (statusLabel.isNotEmpty) deliveryStatusChip(statusLabel),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.green.withOpacity(0.25)),
              ),
              child: Text(
                'Earning: ₹${formatMoney(earningAmount)}',
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.orange.withOpacity(0.25)),
              ),
              child: Text(
                'Payment: ${(item['payment_method'] ?? '-').toString()} / ${(item['payment_status'] ?? '-').toString()}',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          children: [
            if (showOpen) OutlinedButton(onPressed: onView, child: const Text('View')),
            if (showAccept) ElevatedButton(onPressed: onAccept, child: const Text('Accept')),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Seller Details', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...uniqueSellers.map<Widget>((seller) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('👤 Name: ${seller['seller_name'] ?? '-'}'),
                Text('📞 Mobile: ${seller['seller_mobile'] ?? '-'}'),
                Text('🏪 Shop: ${seller['shop_name'] ?? '-'}'),
                Text('📍 Address: ${seller['shop_address'] ?? '-'}'),
                Text('📮 Pincode: ${seller['seller_pincode'] ?? '-'}'),
                const SizedBox(height: 6),
                Builder(
                  builder: (ctx) {
                    final int orderId = int.tryParse((item['order_id'] ?? 0).toString()) ?? 0;
                    int sellerId = int.tryParse((seller['seller_id'] ?? '').toString()) ?? 0;
                    if (sellerId == 0 && item['sellers'] is List) {
                      final sellers = List<dynamic>.from(item['sellers']);
                      if (sellers.isNotEmpty) {
                        sellerId = int.tryParse((Map<String, dynamic>.from(sellers.first)['seller_id'] ?? '').toString()) ?? 0;
                      }
                    }
                    if (orderId == 0 || sellerId == 0) {
                      return const Text('Products: -', style: TextStyle(color: Colors.black54));
                    }
                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: fetchSellerProducts(orderId, sellerId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Text('Products: Unable to load', style: TextStyle(color: Colors.redAccent));
                        }
                        final products = snapshot.data ?? const <Map<String, dynamic>>[];
                        if (products.isEmpty) {
                          return const Text('Products: No products found', style: TextStyle(color: Colors.black54));
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Purchased Products', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            ...products.map((product) {
                              final productName = (product['prod_name'] ?? '-').toString();
                              final quantity = (product['quantity'] ?? 0).toString();
                              final price = (product['price'] ?? '').toString();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text('• $productName  |  Qty: $quantity${price.isNotEmpty ? '  |  ₹$price' : ''}', style: const TextStyle(color: Colors.black87)),
                              );
                            }),
                          ],
                        );
                      },
                    );
                  },
                ),
                const Divider(),
              ],
            ),
          );
        }).toList(),
        const SizedBox(height: 10),
        const Text('User Details', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('👤 Name: ${item['user_name'] ?? '-'}'),
        Text('📞 Mobile: ${item['user_mobile'] ?? '-'}'),
        Text('🏠 Address: ${item['user_address'] ?? '-'}'),
        Text('📮 Pincode: ${item['user_pincode'] ?? '-'}'),
      ],
    ),
  );
}

String? imageUrlFromPath(dynamic value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;

  var cleaned = raw.startsWith('/') ? raw.substring(1) : raw;
  if (!cleaned.startsWith('uploads/')) {
    cleaned = 'uploads/$cleaned';
  }

  final encodedSegments = cleaned
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');

  return ApiConfig.fileUrl(encodedSegments);
}

Widget deliveryProfileAvatar({
  required Map<String, dynamic> profile,
  double radius = 34,
  IconData fallbackIcon = Icons.person,
}) {
  final imageUrl = imageUrlFromPath(profile['profile_image']);
  if (imageUrl != null) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.withOpacity(0.12),
      backgroundImage: NetworkImage(imageUrl),
      onBackgroundImageError: (_, __) {},
    );
  }

  return CircleAvatar(
    radius: radius,
    backgroundColor: Colors.deepPurple.withOpacity(0.12),
    child: Icon(fallbackIcon, size: radius, color: Colors.deepPurple),
  );
}