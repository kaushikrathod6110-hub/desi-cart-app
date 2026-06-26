import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:my_app/admin/admin_MyProfile_page.dart';
import 'package:my_app/admin/admin_Notification_page.dart';
import 'package:my_app/admin/all_orders_page.dart';
import 'package:my_app/admin/all_products_page.dart';
import 'package:my_app/admin/all_sellers_page.dart';
import 'package:my_app/admin/all_users_page.dart';
import 'package:my_app/admin/all_delivery_staff_page.dart';
import 'package:my_app/admin/manageCategory_page.dart';
import 'package:my_app/admin/reports_page.dart';
import 'package:my_app/screens/login_page.dart';

import '../../admin/Admin_Setting_page.dart';
import '../screens/token_storage.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool dashboardLoading = true;
  Map<String, dynamic> counts = {};
  Map<String, dynamic> alerts = {};
  List<dynamic> recentOrders = [];
  String profileImageUrl = '';

  @override
  void initState() {
    super.initState();
    loadAdminData();
    loadDashboardSummary();
    loadProfileImage();
    loadBlockRequestCount();
  }

  int unreadRequestCount = 0;

  Future<void> loadBlockRequestCount() async {
    try {
      final token = await _getToken();
      final response = await http.get(
        ApiConfig.uri('/api/admin/block-requests'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          unreadRequestCount = (data as List).length;
        });
      }
    } catch (_) {}
  }

  Future<String> _getToken() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token missing. Please login again.');
    }
    return token;
  }

  Future<void> loadAdminData() async {
    final storage = TokenStorage();
    String? accessToken = await storage.getAccessToken();

    if (accessToken == null) return;

    final response = await http.get(
      ApiConfig.uri('/api/admin-data'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print(data['message']);
    }
  }

  Future<void> loadProfileImage() async {
    try {
      final storage = TokenStorage();
      final String? token = await storage.getAccessToken();

      if (token == null || token.isEmpty) return;

      final response = await http.get(
        ApiConfig.uri('/api/admin-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;
        setState(() {
          profileImageUrl =
              _normalizeImageUrl((data['profile_image_url'] ?? '').toString());
        });
      }
    } catch (_) {}
  }

  String _normalizeImageUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }

    var clean = value.replaceAll('\\', '/');
    while (clean.startsWith('/')) {
      clean = clean.substring(1);
    }
    if (clean.startsWith('uploads/')) {
      clean = clean.substring('uploads/'.length);
    }
    return ApiConfig.fileUrl('uploads/$clean');
  }

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  String _asText(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  String _money(dynamic value) {
    if (value == null) return '0';
    if (value is num) {
      if (value % 1 == 0) return value.toInt().toString();
      return value.toStringAsFixed(2);
    }
    final parsed = double.tryParse(value.toString()) ?? 0;
    if (parsed % 1 == 0) return parsed.toInt().toString();
    return parsed.toStringAsFixed(2);
  }

  Future<void> loadDashboardSummary() async {
    setState(() => dashboardLoading = true);

    try {
      final token = await _getToken();

      final response = await http.get(
        ApiConfig.uri('/api/admin/dashboard/summary'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Dashboard API failed: ${response.statusCode} ${response.body}',
        );
      }

      final data = jsonDecode(response.body);

      if (!mounted) return;
      setState(() {
        counts = (data['counts'] ?? {}) as Map<String, dynamic>;
        alerts = (data['alerts'] ?? {}) as Map<String, dynamic>;
        recentOrders = (data['recent_orders'] ?? []) as List<dynamic>;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Dashboard error: $e')));
      }
    } finally {
      if (mounted) setState(() => dashboardLoading = false);
    }
  }

  Widget _buildAppBarProfileAvatar() {
    final Widget placeholder = Container(
      width: 36,
      height: 36,
      color: Colors.white,
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.blue),
    );

    final Widget content = profileImageUrl.isNotEmpty
        ? Image.network(
      profileImageUrl,
      fit: BoxFit.cover,
      width: 36,
      height: 36,
      errorBuilder: (_, __, ___) => placeholder,
    )
        : placeholder;

    return ClipOval(child: content);
  }

  void _openPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  TextStyle _linkStyle() {
    return const TextStyle(
      color: Colors.blue,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );
  }

  Widget _dashboardCard({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 235,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _alertChip({
    required String label,
    required int count,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.deepPurple.shade200),
          color: Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.deepPurple),
            const SizedBox(width: 8),
            Text(
              '$label: $count',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showInfoDialog({
    required String title,
    required List<Widget> children,
  }) async {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 620,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showUserDetails(int userId) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        ApiConfig.uri('/api/admin/users/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = Map<String, dynamic>.from(jsonDecode(res.body));

      await _showInfoDialog(
        title: 'User Details',
        children: [
          Text('User ID: ${data['user_id'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Name: ${data['user_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Email: ${data['user_email'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Mobile: ${data['user_mobile'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Address: ${data['user_address'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Pincode: ${data['pincode'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Status: ${data['status'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Registration: ${data['registration_at'] ?? '-'}'),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User details error: $e')),
        );
      }
    }
  }

  Future<void> _showSellerDetails(int sellerId) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        ApiConfig.uri('/api/admin/sellers/$sellerId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = Map<String, dynamic>.from(jsonDecode(res.body));

      await _showInfoDialog(
        title: 'Seller Details',
        children: [
          Text('Seller ID: ${data['seller_id'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Name: ${data['seller_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Email: ${data['seller_email'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Mobile: ${data['seller_mobile'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Shop Name: ${data['shop_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Shop Address: ${data['shop_address'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Pincode: ${data['pincode'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Licence No: ${data['licence_no'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Status: ${data['status'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Registration: ${data['registration_date'] ?? '-'}'),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Seller details error: $e')),
        );
      }
    }
  }

  Future<void> _showDeliveryStaffDetails(int staffId) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        ApiConfig.uri('/api/admin/delivery-staff/$staffId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = Map<String, dynamic>.from(jsonDecode(res.body));
      final imageUrl = (data['profile_image_url'] ?? '').toString();

      await _showInfoDialog(
        title: 'Delivery Staff Details',
        children: [
          if (imageUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                    const CircleAvatar(radius: 50, child: Icon(Icons.person)),
                  ),
                ),
              ),
            ),
          Text('ID: ${data['delivery_staff_id'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Name: ${data['delivery_staff_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Email: ${data['d_s_email'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Mobile: ${data['d_s_mobile'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Address: ${data['d_s_address'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Pincode: ${data['d_s_pincode'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Vehicle: ${data['vehicle_type'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Licence No: ${data['staff_licence_no'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Aadhar: ${data['aadhar_card_no'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Status: ${data['d_s_status'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Joining Date: ${data['joining_date'] ?? '-'}'),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delivery staff details error: $e')),
        );
      }
    }
  }

  Future<void> _showProductDetails(int prodId) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        ApiConfig.uri('/api/admin/products/$prodId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final data = Map<String, dynamic>.from(jsonDecode(res.body));
      final imageUrls = [
        (data['prod_image'] ?? '').toString(),
        (data['prod_image2'] ?? '').toString(),
        (data['prod_image3'] ?? '').toString(),
      ].where((e) => e.trim().isNotEmpty).map((e) => _normalizeImageUrl(e)).toList();

      await _showInfoDialog(
        title: 'Product Details',
        children: [
          if (imageUrls.isNotEmpty)
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, index) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      imageUrls[index],
                      width: 130,
                      height: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 130,
                        height: 130,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (imageUrls.isNotEmpty) const SizedBox(height: 12),
          Text('Product ID: ${data['prod_id'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Name: ${data['prod_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Brand: ${data['brand'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Category: ${data['category_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Seller: ${data['seller_name'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Price: ₹${data['prod_price'] ?? 0}'),
          const SizedBox(height: 8),
          Text('Stock Quantity: ${data['stock_quantity'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Unit: ${data['unit_type'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Stock Status: ${data['stock_status'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Product Status: ${data['prod_status'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Expiry: ${data['expiry_at'] ?? '-'}'),
          const SizedBox(height: 8),
          Text('Description: ${data['description'] ?? '-'}'),
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product details error: $e')),
        );
      }
    }
  }

  Widget _clickableLabel({
    required String label,
    required String value,
    required VoidCallback? onTap,
  }) {
    final hasTap = onTap != null && value.trim().isNotEmpty && value.trim() != '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        children: [
          Text('$label: '),
          GestureDetector(
            onTap: hasTap ? onTap : null,
            child: Text(
              value.isEmpty ? '-' : value,
              style: hasTap ? _linkStyle() : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDashboardOrderDetails(int orderId) async {
    try {
      final token = await _getToken();

      final response = await http.get(
        ApiConfig.uri('/api/admin/orders/$orderId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Order details failed: ${response.statusCode} ${response.body}');
      }

      final data = Map<String, dynamic>.from(jsonDecode(response.body));
      final products = List<dynamic>.from(data['products'] ?? []);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: 820,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order #${data['order_id'] ?? ''}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Chip(label: Text('Order Status: ${data['order_status'] ?? '-'}')),
                      Chip(label: Text('Payment: ${data['payment_status'] ?? '-'}')),
                      Chip(label: Text('Method: ${data['payment_method'] ?? '-'}')),
                      Chip(label: Text('Amount: ₹${_money(data['total_amount'])}')),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _clickableLabel(
                    label: 'Seller',
                    value: (data['seller_name'] ?? '—').toString(),
                    onTap: data['seller_id'] != null
                        ? () => _showSellerDetails(int.parse(data['seller_id'].toString()))
                        : null,
                  ),
                  _clickableLabel(
                    label: 'User',
                    value: (data['user_name'] ?? '—').toString(),
                    onTap: data['user_id'] != null
                        ? () => _showUserDetails(int.parse(data['user_id'].toString()))
                        : null,
                  ),
                  _clickableLabel(
                    label: 'Delivery Staff',
                    value: (data['delivery_staff_name'] ?? '—').toString(),
                    onTap: data['delivery_staff_id'] != null
                        ? () => _showDeliveryStaffDetails(
                      int.parse(data['delivery_staff_id'].toString()),
                    )
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Date: ${data['order_date'] ?? '-'}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Address: ${data['delivery_address'] ?? '-'}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Pincode: ${data['pincode'] ?? '-'}'),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Notes: ${data['notes'] ?? '-'}'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Products',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (products.isEmpty)
                    const Text('No product details available')
                  else
                    ...products.map((p) {
                      final prodId = int.tryParse((p['product_id'] ?? '').toString()) ?? 0;
                      final imageUrl = _normalizeImageUrl(
                        (p['product_image'] ?? p['prod_image'] ?? '').toString(),
                      );

                      return InkWell(
                        onTap: prodId > 0 ? () => _showProductDetails(prodId) : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: prodId > 0 ? () => _showProductDetails(prodId) : null,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: imageUrl.isNotEmpty
                                        ? Image.network(
                                      imageUrl,
                                      width: 72,
                                      height: 72,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 72,
                                        height: 72,
                                        color: Colors.grey.shade200,
                                        child: const Icon(Icons.broken_image),
                                      ),
                                    )
                                        : Container(
                                      width: 72,
                                      height: 72,
                                      color: Colors.grey.shade200,
                                      child: const Icon(Icons.image_not_supported),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: prodId > 0 ? () => _showProductDetails(prodId) : null,
                                        child: Text(
                                          (p['product_name'] ?? 'Unnamed Product').toString(),
                                          style: prodId > 0
                                              ? _linkStyle().copyWith(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          )
                                              : const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text('Qty: ${p['ordered_qty'] ?? p['stock_quantity'] ?? '-'}'),
                                      Text('Price: ₹${_money(p['ordered_price'] ?? p['price'])}'),
                                      Text('Total: ₹${_money(p['ordered_total'] ?? p['price'])}'),
                                      if ((p['brand'] ?? '').toString().isNotEmpty)
                                        Text('Brand: ${p['brand']}'),
                                      if ((p['unit_type'] ?? '').toString().isNotEmpty)
                                        Text('Unit: ${p['unit_type']}'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Order details error: $e')),
        );
      }
    }
  }

  Widget _buildRecentOrderTile(dynamic o) {
    final id = _asText(o['order_id']);
    final amt = _asText(o['total_amount']);
    final st = _asText(o['order_status']);
    final pay = _asText(o['payment_status']);
    final dt = _asText(o['order_date']);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        final parsedId = int.tryParse(id) ?? 0;
        if (parsedId > 0) {
          _showDashboardOrderDetails(parsedId);
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.receipt_long),
          title: Text('Order #$id  •  ₹$amt'),
          subtitle: Text('Status: $st | Payment: $pay | $dt'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final outOfStock = _asInt(alerts['out_of_stock']);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: const Text('Admin Home Page!'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: IconButton(
              icon: const Icon(Icons.notifications),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminNotificationPage(),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdminMyprofilePage(),
                  ),
                );
                await loadProfileImage();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: _buildAppBarProfileAvatar(),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Admin Menu',
                style: TextStyle(color: Colors.white, fontSize: 30),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('Manage Category'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ManagecategoryPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.people),
              title: const Text('All Sellers'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllSellersPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_sharp),
              title: const Text('All Users'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllUsersPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping),
              title: const Text('All Delivery Staff'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AllDeliveryStaffPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('All Products'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllProductsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_bag_sharp),
              title: const Text('All Orders'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AllOrdersPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bar_chart),
              title: const Text('Reports'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ReportsPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AdminSettingPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: Colors.red.shade500),
              title: Text(
                'Log Out',
                style: TextStyle(color: Colors.red.shade500),
              ),
              onTap: () async {
                final storage = TokenStorage();
                await storage.deleteTokens();

                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => LoginPage()),
                      (_) => false,
                );
              },
            ),
          ],
        ),
      ),
      body: dashboardLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: () async {
          await loadDashboardSummary();
          await loadProfileImage();
        },
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _dashboardCard(
                  title: 'Total Users',
                  value: '${counts['total_users'] ?? 0}',
                  icon: Icons.people,
                  onTap: () => _openPage(const AllUsersPage()),
                ),
                _dashboardCard(
                  title: 'Total Sellers',
                  value: '${counts['total_sellers'] ?? 0}',
                  icon: Icons.store,
                  onTap: () => _openPage(const AllSellersPage()),
                ),
                _dashboardCard(
                  title: 'Total Delivery Staff',
                  value: '${counts['total_delivery_staff'] ?? 0}',
                  icon: Icons.local_shipping,
                  onTap: () => _openPage(const AllDeliveryStaffPage()),
                ),
                _dashboardCard(
                  title: 'Total Products',
                  value: '${counts['total_products'] ?? 0}',
                  icon: Icons.inventory_2,
                  onTap: () => _openPage(const AllProductsPage()),
                ),
                _dashboardCard(
                  title: 'Total Orders',
                  value: '${counts['total_orders'] ?? 0}',
                  icon: Icons.shopping_bag,
                  onTap: () => _openPage(const AllOrdersPage()),
                ),
                _dashboardCard(
                  title: 'Today Orders',
                  value: '${counts['today_orders'] ?? 0}',
                  icon: Icons.today,
                  onTap: () => _openPage(const AllOrdersPage(filter: 'today')),
                ),
                _dashboardCard(
                  title: 'Today Revenue',
                  value: '₹${counts['today_revenue'] ?? 0}',
                  icon: Icons.currency_rupee,
                  onTap: () =>
                      _openPage(const AllOrdersPage(filter: 'today_revenue')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _alertChip(
                      label: 'Out of Stock',
                      count: outOfStock,
                      icon: Icons.info_outline,
                      onTap: () =>
                          _openPage(const AllProductsPage(filter: 'out_of_stock')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Recent Orders',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _openPage(const AllOrdersPage()),
                          child: const Text('View All'),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          onPressed: loadDashboardSummary,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (recentOrders.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No recent orders found'),
                      )
                    else
                      ...recentOrders.map(_buildRecentOrderTile).toList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}