import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;

import '../screens/token_storage.dart';
import 'common/admin_list_widgets.dart';

class AllSellersPage extends StatefulWidget {
  const AllSellersPage({super.key});

  @override
  State<AllSellersPage> createState() => _AllSellersPageState();
}

class _AllSellersPageState extends State<AllSellersPage> {
  bool isLoading = true;
  bool showOverview = true;

  int total = 0;
  int activeNew = 0;
  int activeOld = 0;
  int inactiveNew = 0;
  int inactiveOld = 0;

  List<dynamic> sellers = [];
  String query = '';

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    setState(() => isLoading = true);

    try {
      final storage = TokenStorage();
      final token = await storage.getAccessToken();
      if (token == null) throw Exception('Token missing. Please login again.');

      final statsRes = await http.get(
        ApiConfig.uri('/api/admin/sellers/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (statsRes.statusCode != 200) {
        throw Exception('Stats error: ${statsRes.statusCode} ${statsRes.body}');
      }
      final stats = jsonDecode(statsRes.body);

      final listRes = await http.get(
        ApiConfig.uri('/api/admin/sellers'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (listRes.statusCode != 200) {
        throw Exception('List error: ${listRes.statusCode} ${listRes.body}');
      }
      final list = jsonDecode(listRes.body);

      setState(() {
        total = (stats['total'] ?? 0) as int;
        activeNew = (stats['active_new'] ?? 0) as int;
        activeOld = (stats['active_old'] ?? 0) as int;
        inactiveNew = (stats['inactive_new'] ?? 0) as int;
        inactiveOld = (stats['inactive_old'] ?? 0) as int;
        sellers = list is List ? list : [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> updateSellerStatus(int sellerId, String newStatus) async {
    try {
      final storage = TokenStorage();
      final token = await storage.getAccessToken();
      if (token == null) throw Exception('Token missing. Please login again.');

      final res = await http.put(
        ApiConfig.uri('/api/admin/sellers/$sellerId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': newStatus}),
      );

      if (res.statusCode == 200) {
        await loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                newStatus == 'inactive'
                    ? 'Seller blocked successfully'
                    : 'Seller unblocked successfully',
              ),
            ),
          );
        }
      } else {
        final body = jsonDecode(res.body);
        throw Exception(body['error'] ?? body['message'] ?? res.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e')),
        );
      }
    }
  }

  List<dynamic> get filteredSellers {
    if (query.trim().isEmpty) return sellers;
    final q = query.toLowerCase();

    return sellers.where((s) {
      final name = (s['seller_name'] ?? '').toString().toLowerCase();
      final email = (s['seller_email'] ?? '').toString().toLowerCase();
      final mobile = (s['seller_mobile'] ?? '').toString().toLowerCase();
      final shop = (s['shop_name'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          email.contains(q) ||
          mobile.contains(q) ||
          shop.contains(q);
    }).toList();
  }

  Map<String, dynamic> _mapFrom(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  String _text(dynamic value, {String fallback = '-'}) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _amount(dynamic value) {
    if (value == null) return '0';
    if (value is num) {
      final number = value.toDouble();
      return number == number.roundToDouble()
          ? number.toInt().toString()
          : number.toStringAsFixed(2);
    }
    final parsed = double.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return parsed == parsed.roundToDouble()
        ? parsed.toInt().toString()
        : parsed.toStringAsFixed(2);
  }

  Widget _buildInfoRow(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewSection(List<PieSegment> segments) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Overview',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => showOverview = !showOverview),
                    icon: Icon(
                      showOverview ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    ),
                    label: Text(showOverview ? 'Hide graph' : 'Show graph'),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: showOverview
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    Transform.scale(
                      scale: MediaQuery.of(context).size.width >= 1000 ? 0.88 : 0.82,
                      alignment: Alignment.topCenter,
                      child: AdminResponsiveSection(total: total, segments: segments),
                    ),
                    const SizedBox(height: 8),
                    AdminStatsChips(
                      total: total,
                      active: activeNew + activeOld,
                      inactive: inactiveNew + inactiveOld,
                      newCount: activeNew + inactiveNew,
                      oldCount: activeOld + inactiveOld,
                    ),
                  ],
                ),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AdminStatsChips(
                    total: total,
                    active: activeNew + activeOld,
                    inactive: inactiveNew + inactiveOld,
                    newCount: activeNew + inactiveNew,
                    oldCount: activeOld + inactiveOld,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> showSellerDetails(int sellerId) async {
    try {
      final storage = TokenStorage();
      final token = await storage.getAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token missing. Please login again.');
      }

      final res = await http.get(
        ApiConfig.uri('/api/admin/sellers/$sellerId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) throw Exception(res.body);

      final raw = jsonDecode(res.body);
      final data = _mapFrom(raw);
      if (!mounted) return;

      final stats = _mapFrom(data['stats']);
      final seller = data.containsKey('seller') ? _mapFrom(data['seller']) : data;

      final sellerName = _text(seller['seller_name']);
      final sellerEmail = _text(seller['seller_email']);
      final sellerMobile = _text(seller['seller_mobile']);
      final shopName = _text(seller['shop_name']);
      final shopAddress = _text(seller['shop_address']);
      final pincode = _text(seller['pincode']);
      final licenceNo = _text(seller['licence_no']);
      final status = _text(seller['status'], fallback: 'active');

      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          child: Text(
                            sellerName.isNotEmpty ? sellerName[0].toUpperCase() : 'S',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sellerName,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                shopName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: status.toLowerCase() == 'active'
                                ? Colors.green.withOpacity(0.10)
                                : Colors.red.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: status.toLowerCase() == 'active'
                                  ? Colors.green.withOpacity(0.35)
                                  : Colors.red.withOpacity(0.35),
                            ),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: status.toLowerCase() == 'active'
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        AdminMiniStatTile(
                          label: 'Total Products',
                          value: '${stats['total_products'] ?? 0}',
                        ),
                        AdminMiniStatTile(
                          label: 'Total Orders',
                          value: '${stats['total_orders'] ?? 0}',
                        ),
                        AdminMiniStatTile(
                          label: 'Revenue',
                          value: '₹${_amount(stats['total_revenue'])}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Seller Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow('Email', sellerEmail, icon: Icons.email_outlined),
                    _buildInfoRow('Mobile', sellerMobile, icon: Icons.phone_outlined),
                    _buildInfoRow('Shop Name', shopName, icon: Icons.storefront_outlined),
                    _buildInfoRow('Address', shopAddress, icon: Icons.location_on_outlined),
                    _buildInfoRow('Pincode', pincode, icon: Icons.pin_drop_outlined),
                    _buildInfoRow('Licence No.', licenceNo, icon: Icons.badge_outlined),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Details error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = [
      PieSegment(label: 'Active-New', value: activeNew),
      PieSegment(label: 'Active-Old', value: activeOld),
      PieSegment(label: 'Inactive-New', value: inactiveNew),
      PieSegment(label: 'Inactive-Old', value: inactiveOld),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Sellers'),
        actions: [
          IconButton(
            onPressed: isLoading ? null : loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildOverviewSection(segments),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search seller (name/email/mobile/shop)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredSellers.isEmpty
                  ? const Center(child: Text('No sellers found'))
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: filteredSellers.length,
                itemBuilder: (context, index) {
                  final s = filteredSellers[index];

                  final id = int.tryParse((s['seller_id'] ?? '').toString()) ?? 0;
                  final name = (s['seller_name'] ?? '').toString();
                  final email = (s['seller_email'] ?? '').toString();
                  final mobile = (s['seller_mobile'] ?? '').toString();
                  final shop = (s['shop_name'] ?? '').toString();
                  final status = (s['status'] ?? 'active').toString().toLowerCase();

                  final isActive = status == 'active';

                  return AdminItemCard(
                    onTap: id == 0 ? null : () => showSellerDetails(id),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    title: name,
                    lines: [email, mobile, 'Shop: $shop'],
                    trailing: StatusActionTrailing(
                      isActive: isActive,
                      compact: MediaQuery.of(context).size.width < 700,
                      onPressed: id == 0
                          ? null
                          : () async {
                        final nextStatus = isActive ? 'inactive' : 'active';

                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(
                              isActive ? 'Block Seller?' : 'Unblock Seller?',
                            ),
                            content: Text(
                              isActive
                                  ? 'If you block this seller, their login and access will be stopped.'
                                  : 'If you unblock this seller, their login and access will be restored.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Yes'),
                              ),
                            ],
                          ),
                        );

                        if (ok == true) {
                          await updateSellerStatus(id, nextStatus);
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}