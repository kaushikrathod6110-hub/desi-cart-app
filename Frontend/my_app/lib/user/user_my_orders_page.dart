import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_order_details_page.dart';
import 'package:my_app/user/user_profile_page.dart';

class UserMyOrdersPage extends StatefulWidget {
  const UserMyOrdersPage({super.key});

  @override
  State<UserMyOrdersPage> createState() => _UserMyOrdersPageState();
}

class _UserMyOrdersPageState extends State<UserMyOrdersPage> {
  bool isLoading = true;
  List orders = [];
  Timer? _ticker;
  DateTime nowTime = DateTime.now();
  String searchQuery = '';
  String selectedStatus = 'all';
  String selectedTime = 'all';
  int? selectedSellerId;

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => nowTime = DateTime.now());
    });
    fetchOrders();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> fetchOrders() async {
    setState(() => isLoading = true);

    try {
      final res = await http.get(
        ApiConfig.uri('/api/user/orders'),
        headers: await getHeaders(),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['success'] == true) {
        setState(() {
          orders = data['orders'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']?.toString() ?? 'Failed to load orders')),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order loading error: $e')),
      );
    }
  }

  Future<void> cancelOrderFromList(int orderId) async {
    try {
      final res = await http.put(
        ApiConfig.uri('/api/user/orders/$orderId/cancel'),
        headers: await getHeaders(),
      );

      final data = jsonDecode(res.body);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message']?.toString() ?? 'Response received')),
      );

      if (res.statusCode == 200 && data['success'] == true) {
        await fetchOrders();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancel error: $e')),
      );
    }
  }


  int remainingCancelSeconds(Map<String, dynamic> order) {
    final orderDate = parseOrderDate(order['order_date']);
    if (orderDate == null) return 0;
    final end = orderDate.add(const Duration(minutes: 5));
    final diff = end.difference(nowTime).inSeconds;
    return diff > 0 ? diff : 0;
  }

  String formatRemaining(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  bool canCancelOrder(Map<String, dynamic> order) {
    if (order['can_cancel'] == true) {
      return remainingCancelSeconds(order) > 0;
    }
    return false;
  }

  Color statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'confirmed':
      case 'packed':
      case 'outfordelivery':
      case 'out for delivery':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${dt.day}/${dt.month}/${dt.year}  $hour:${dt.minute.toString().padLeft(2, '0')} $ampm';
    } catch (_) {
      return raw;
    }
  }

  DateTime? parseOrderDate(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }


  String effectiveStatus(Map<String, dynamic> order) {
    final tracking = (order['tracking_status'] ?? '').toString().trim();
    if (tracking.isNotEmpty) return tracking;
    final delivery = (order['delivery_status'] ?? '').toString().trim();
    if (delivery.isNotEmpty) return delivery;
    return (order['order_status'] ?? '').toString();
  }

  Widget buildChip(String text, Color color, {bool filled = true}) {
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

  List<Map<String, dynamic>> get filteredOrders {
    final now = DateTime.now();

    return orders
        .map((e) => Map<String, dynamic>.from(e))
        .where((order) {
      final status = effectiveStatus(order).toLowerCase();
      final deliveryStatus = (order['delivery_status'] ?? '').toString().toLowerCase();
      final sellerId = int.tryParse((order['seller_id'] ?? '').toString());
      final query = searchQuery.trim().toLowerCase();
      final orderDate = parseOrderDate(order['order_date']);

      final combinedText = [
        order['orderId'],
        order['first_item_name'],
        order['seller_name'],
        order['shop_name'],
        order['seller_mobile'],
      ].join(' ').toLowerCase();

      if (query.isNotEmpty && !combinedText.contains(query)) {
        return false;
      }

      if (selectedStatus != 'all') {
        if (selectedStatus == 'out_for_delivery') {
          final normalizedOrder = status.replaceAll(' ', '');
          final normalizedDelivery = deliveryStatus.replaceAll(' ', '');
          if (normalizedOrder != 'outfordelivery' && normalizedDelivery != 'outfordelivery') {
            return false;
          }
        } else if (status != selectedStatus && deliveryStatus != selectedStatus) {
          return false;
        }
      }

      if (selectedSellerId != null && sellerId != selectedSellerId) {
        return false;
      }

      if (selectedTime != 'all' && orderDate != null) {
        if (selectedTime == 'last_30_days' && now.difference(orderDate).inDays > 30) {
          return false;
        }
        if (selectedTime == 'this_year' && orderDate.year != now.year) {
          return false;
        }
        if (selectedTime == 'older') {
          final startOfYear = DateTime(now.year, 1, 1);
          if (!orderDate.isBefore(startOfYear)) {
            return false;
          }
        }
      }

      return true;
    })
        .toList();
  }

  List<Map<String, dynamic>> get sellerOptions {
    final sellers = <String, Map<String, dynamic>>{};
    for (final raw in orders) {
      final order = Map<String, dynamic>.from(raw);
      final sellerId = (order['seller_id'] ?? '').toString();
      if (sellerId.isEmpty) continue;
      sellers.putIfAbsent(sellerId, () => order);
    }
    final list = sellers.values.map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) => ((a['shop_name'] ?? a['seller_name'] ?? '').toString())
        .toLowerCase()
        .compareTo(((b['shop_name'] ?? b['seller_name'] ?? '').toString()).toLowerCase()));
    return list;
  }

  Widget buildFilterChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.blue : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(selected ? Icons.check_circle : Icons.add, color: selected ? Colors.blue : Colors.blue),
          ],
        ),
      ),
    );
  }

  Future<void> openFilters() async {
    String tempStatus = selectedStatus;
    String tempTime = selectedTime;
    int? tempSellerId = selectedSellerId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Filters',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                tempStatus = 'all';
                                tempTime = 'all';
                                tempSellerId = null;
                              });
                            },
                            child: const Text('Clear Filter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Order Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          {'value': 'all', 'label': 'All'},
                          {'value': 'pending', 'label': 'Pending'},
                          {'value': 'confirmed', 'label': 'Confirmed'},
                          {'value': 'packed', 'label': 'Packed'},
                          {'value': 'out_for_delivery', 'label': 'On the way'},
                          {'value': 'delivered', 'label': 'Delivered'},
                          {'value': 'cancelled', 'label': 'Cancelled'},
                        ].map((entry) {
                          return buildFilterChoice(
                            label: entry['label']!,
                            selected: tempStatus == entry['value'],
                            onTap: () => setModalState(() => tempStatus = entry['value']!),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text('Order Time', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          {'value': 'all', 'label': 'All'},
                          {'value': 'last_30_days', 'label': 'Last 30 days'},
                          {'value': 'this_year', 'label': '${DateTime.now().year}'},
                          {'value': 'older', 'label': 'Older'},
                        ].map((entry) {
                          return buildFilterChoice(
                            label: entry['label']!,
                            selected: tempTime == entry['value'],
                            onTap: () => setModalState(() => tempTime = entry['value']!),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text('Seller', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          buildFilterChoice(
                            label: 'All Sellers',
                            selected: tempSellerId == null,
                            onTap: () => setModalState(() => tempSellerId = null),
                          ),
                          ...sellerOptions.map((seller) {
                            final sellerId = int.tryParse((seller['seller_id'] ?? '').toString());
                            final sellerName = (seller['shop_name'] ?? seller['seller_name'] ?? 'Seller').toString();
                            return buildFilterChoice(
                              label: sellerName,
                              selected: tempSellerId == sellerId,
                              onTap: () => setModalState(() => tempSellerId = sellerId),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedStatus = tempStatus;
                                  selectedTime = tempTime;
                                  selectedSellerId = tempSellerId;
                                });
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget buildOrderCard(Map<String, dynamic> order) {
    final firstImage = (order['first_item_image'] ?? '').toString();
    final firstItemName = (order['first_item_name'] ?? 'Order Item').toString();
    final itemCount = int.tryParse(order['item_count'].toString()) ?? 1;
    final status = effectiveStatus(order).toString().isEmpty ? 'Pending' : effectiveStatus(order).toString();
    final paymentStatus = (order['payment_status'] ?? '').toString();
    final sellerName = (order['shop_name'] ?? order['seller_name'] ?? '-').toString();
    final remainingSeconds = remainingCancelSeconds(order);
    final canCancel = canCancelOrder(order);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserOrderDetailsPage(orderId: order['order_id']),
            ),
          );
          await fetchOrders();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: firstImage.isNotEmpty
                          ? Image.network(
                        firstImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.shopping_bag_outlined,
                          size: 34,
                          color: Colors.grey,
                        ),
                      )
                          : const Icon(
                        Icons.shopping_bag_outlined,
                        size: 34,
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
                          firstItemName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          itemCount > 1 ? '$itemCount items' : '1 item',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Seller: $sellerName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            buildChip(status, statusColor(status)),
                            buildChip('Payment: $paymentStatus', Colors.grey, filled: false),
                            if (canCancel) buildChip('Cancel in ${formatRemaining(remainingSeconds)}', Colors.red),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ordered on ${formatDate(order['order_date']?.toString())}',
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    '₹${(order['total_amount'] ?? 0).toString()}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (canCancel)
                    Text(
                      'Cancel available for ${formatRemaining(remainingSeconds)}',
                      style: TextStyle(
                        color: Colors.red.shade400,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserOrderDetailsPage(orderId: order['order_id']),
                        ),
                      );
                      await fetchOrders();
                    },
                    child: const Text(
                      'View Details',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget buildSellerSection(Map<String, dynamic> seller, List<Map<String, dynamic>> sellerOrders) {
    final title = (seller['shop_name'] ?? seller['seller_name'] ?? 'Seller').toString();
    final sellerName = (seller['seller_name'] ?? '').toString();
    final mobile = (seller['seller_mobile'] ?? '').toString();
    final address = (seller['shop_address'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
                if (sellerName.isNotEmpty && sellerName.toLowerCase() != title.toLowerCase()) ...[
                  const SizedBox(height: 4),
                  Text('Seller: $sellerName'),
                ],
                if (mobile.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Contact: $mobile'),
                ],
                if (address.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Address: $address'),
                ],
                const SizedBox(height: 6),
                Text(
                  '${sellerOrders.length} order${sellerOrders.length == 1 ? '' : 's'} from this seller',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          ...sellerOrders.map(buildOrderCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filteredOrders;
    final grouped = <String, List<Map<String, dynamic>>>{};

    if (selectedSellerId != null) {
      for (final order in filtered) {
        final key = (order['seller_id'] ?? '0').toString();
        grouped.putIfAbsent(key, () => []).add(order);
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xfff6f3fb),
      appBar: AppBar(
        title: const Text('My Orders'),
        backgroundColor: Colors.blue,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            );
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: fetchOrders,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) => setState(() => searchQuery = value),
                      decoration: InputDecoration(
                        hintText: 'Search your orders',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: openFilters,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.tune),
                          SizedBox(width: 8),
                          Text('Filters'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (selectedStatus != 'all' || selectedTime != 'all' || selectedSellerId != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: [
                    if (selectedStatus != 'all')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: buildChip('Status: ${selectedStatus.replaceAll('_', ' ')}', Colors.blue),
                      ),
                    if (selectedTime != 'all')
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: buildChip('Time: ${selectedTime.replaceAll('_', ' ')}', Colors.deepPurple),
                      ),
                    if (selectedSellerId != null)
                      buildChip(
                        'Seller: ${sellerOptions.firstWhere(
                              (e) => int.tryParse((e['seller_id'] ?? '').toString()) == selectedSellerId,
                          orElse: () => {'shop_name': 'Selected Seller'},
                        )['shop_name'] ?? 'Selected Seller'}',
                        Colors.green,
                      ),
                  ],
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Icon(Icons.shopping_bag_outlined, size: 84, color: Colors.grey),
                  SizedBox(height: 14),
                  Center(
                    child: Text(
                      'No orders found',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              )
                  : selectedSellerId != null
                  ? ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: grouped.entries.map((entry) {
                  final seller = entry.value.first;
                  return buildSellerSection(seller, entry.value);
                }).toList(),
              )
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  return buildOrderCard(filtered[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}