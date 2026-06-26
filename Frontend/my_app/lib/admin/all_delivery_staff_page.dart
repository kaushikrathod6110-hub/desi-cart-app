import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;

import '../screens/token_storage.dart';
import 'common/admin_list_widgets.dart';

class AllDeliveryStaffPage extends StatefulWidget {
  const AllDeliveryStaffPage({super.key});

  @override
  State<AllDeliveryStaffPage> createState() => _AllDeliveryStaffPageState();
}

class _AllDeliveryStaffPageState extends State<AllDeliveryStaffPage> {
  bool isLoading = true;
  bool showOverview = true;
  int total = 0;
  int activeNew = 0;
  int activeOld = 0;
  int inactiveNew = 0;
  int inactiveOld = 0;
  List<dynamic> staff = [];
  String query = '';

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<String> _getToken() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token missing. Please login again.');
    }
    return token;
  }

  Future<void> loadAll() async {
    setState(() => isLoading = true);
    try {
      final token = await _getToken();
      final statsRes = await http.get(
        ApiConfig.uri('/api/admin/delivery-staff/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final listRes = await http.get(
        ApiConfig.uri('/api/admin/delivery-staff'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (statsRes.statusCode != 200) {
        throw Exception('Stats error: ${statsRes.statusCode} ${statsRes.body}');
      }
      if (listRes.statusCode != 200) {
        throw Exception('List error: ${listRes.statusCode} ${listRes.body}');
      }

      final stats = jsonDecode(statsRes.body);
      final list = jsonDecode(listRes.body);
      setState(() {
        total = (stats['total'] ?? 0) as int;
        activeNew = (stats['active_new'] ?? 0) as int;
        activeOld = (stats['active_old'] ?? 0) as int;
        inactiveNew = (stats['inactive_new'] ?? 0) as int;
        inactiveOld = (stats['inactive_old'] ?? 0) as int;
        staff = list is List ? list : [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> updateStaffStatus(int staffId, String newStatus) async {
    try {
      final token = await _getToken();
      final res = await http.put(
        ApiConfig.uri('/api/admin/delivery-staff/$staffId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': newStatus}),
      );
      if (res.statusCode == 200) {
        await loadAll();
      } else {
        throw Exception(res.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e')),
        );
      }
    }
  }

  List<dynamic> get filteredStaff {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return staff;
    return staff.where((s) {
      return (s['delivery_staff_name'] ?? '').toString().toLowerCase().contains(q) ||
          (s['d_s_email'] ?? '').toString().toLowerCase().contains(q) ||
          (s['d_s_mobile'] ?? '').toString().toLowerCase().contains(q) ||
          (s['vehicle_type'] ?? '').toString().toLowerCase().contains(q);
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

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
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

  Future<void> _showDetails(int staffId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final token = await _getToken();
      final res = await http.get(
        ApiConfig.uri('/api/admin/delivery-staff/$staffId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (res.statusCode != 200) throw Exception(res.body);

      final data = _mapFrom(jsonDecode(res.body));
      final profile = data['profile'] != null ? _mapFrom(data['profile']) : data;
      final stats = _mapFrom(data['stats']);
      final summary = _mapFrom(data['summary']);
      final recentOrders = List<dynamic>.from(data['recent_orders'] ?? []);

      final staffName = _text(profile['delivery_staff_name']);
      final email = _text(profile['d_s_email']);
      final mobile = _text(profile['d_s_mobile']);
      final address = _text(profile['d_s_address']);
      final pincode = _text(profile['d_s_pincode']);
      final vehicle = _text(profile['vehicle_type']);
      final licenceNo = _text(profile['staff_licence_no']);
      final status = _text(profile['d_s_status'], fallback: 'Active');

      final totalOrders = _asInt(stats['total_orders'] ?? summary['total_assigned']);
      final deliveredOrders = _asInt(stats['delivered_orders'] ?? summary['delivered_orders']);
      final activeOrders = _asInt(stats['active_orders'] ?? summary['active_orders']);
      final paidOrders = _asInt(stats['paid_orders']);

      await showDialog(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          child: Icon(Icons.local_shipping_outlined),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                staffName,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                vehicle,
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
                          label: 'Staff ID',
                          value: '${profile['delivery_staff_id'] ?? staffId}',
                        ),
                        AdminMiniStatTile(
                          label: 'Total Orders',
                          value: '$totalOrders',
                        ),
                        AdminMiniStatTile(
                          label: 'Delivered',
                          value: '$deliveredOrders',
                        ),
                        AdminMiniStatTile(
                          label: 'Active Orders',
                          value: '$activeOrders',
                        ),
                        AdminMiniStatTile(
                          label: 'Paid Orders',
                          value: '$paidOrders',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Staff Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow('Email', email, icon: Icons.email_outlined),
                    _buildInfoRow('Mobile', mobile, icon: Icons.phone_outlined),
                    _buildInfoRow('Address', address, icon: Icons.location_on_outlined),
                    _buildInfoRow('Pincode', pincode, icon: Icons.pin_drop_outlined),
                    _buildInfoRow('Vehicle', vehicle, icon: Icons.two_wheeler_outlined),
                    _buildInfoRow('Licence No.', licenceNo, icon: Icons.badge_outlined),
                    const SizedBox(height: 10),
                    const Text(
                      'Recent Orders',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    if (recentOrders.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.grey.shade100,
                        ),
                        child: const Text('No recent orders'),
                      )
                    else
                      ...recentOrders.take(5).map(
                            (order) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.receipt_long_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Order #${order['order_id'] ?? '-'}',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Amount: ₹${_amount(order['total_amount'])}'),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Order: ${_text(order['order_status'])} • Delivery: ${_text(order['delivery_status'])} • Payment: ${_text(order['payment_status'])}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
        Navigator.of(context, rootNavigator: true).maybePop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to load details: $e')),
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
        title: const Text('All Delivery Staff'),
        actions: [
          IconButton(onPressed: isLoading ? null : loadAll, icon: const Icon(Icons.refresh)),
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
                  labelText: 'Search delivery staff (name/email/mobile/vehicle)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredStaff.isEmpty
                  ? const Center(child: Text('No delivery staff found'))
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: filteredStaff.length,
                itemBuilder: (context, index) {
                  final s = filteredStaff[index];
                  final id = int.tryParse((s['delivery_staff_id'] ?? '').toString()) ?? 0;
                  final isActive = (s['d_s_status'] ?? 'Active').toString().toLowerCase() == 'active';
                  return AdminItemCard(
                    onTap: id == 0 ? null : () => _showDetails(id),
                    leading: const CircleAvatar(radius: 24, child: Icon(Icons.local_shipping)),
                    title: (s['delivery_staff_name'] ?? '').toString(),
                    lines: [
                      (s['d_s_email'] ?? '').toString(),
                      (s['d_s_mobile'] ?? '').toString(),
                      'Vehicle: ${(s['vehicle_type'] ?? '-').toString()}',
                    ],
                    trailing: StatusActionTrailing(
                      isActive: isActive,
                      actionActiveText: 'Disable',
                      actionInactiveText: 'Enable',
                      compact: MediaQuery.of(context).size.width < 700,
                      onPressed: id == 0
                          ? null
                          : () async {
                        final next = isActive ? 'Inactive' : 'Active';
                        await updateStaffStatus(id, next);
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