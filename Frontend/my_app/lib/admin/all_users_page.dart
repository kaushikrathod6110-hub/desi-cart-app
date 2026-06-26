import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;

import '../screens/token_storage.dart';
import 'common/admin_list_widgets.dart';

class AllUsersPage extends StatefulWidget {
  const AllUsersPage({super.key});

  @override
  State<AllUsersPage> createState() => _AllUsersPageState();
}

class _AllUsersPageState extends State<AllUsersPage> {
  bool isLoading = true;
  bool showOverview = true;

  int total = 0;
  int activeNew = 0;
  int activeOld = 0;
  int inactiveNew = 0;
  int inactiveOld = 0;

  List<dynamic> users = [];
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

      if (token == null || token.isEmpty) {
        throw Exception('Token missing. Please login again.');
      }

      final statsRes = await http.get(
        ApiConfig.uri('/api/admin/users/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (statsRes.statusCode != 200) {
        throw Exception('Stats error: ${statsRes.statusCode} ${statsRes.body}');
      }

      final stats = jsonDecode(statsRes.body);

      final listRes = await http.get(
        ApiConfig.uri('/api/admin/users'),
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
        users = list is List ? list : [];
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

  Future<void> updateUserStatus(int userId, String newStatus) async {
    try {
      final storage = TokenStorage();
      final token = await storage.getAccessToken();

      if (token == null || token.isEmpty) {
        throw Exception('Token missing. Please login again.');
      }

      final res = await http.put(
        ApiConfig.uri('/api/admin/users/$userId/status'),
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
                    ? 'User blocked successfully'
                    : 'User unblocked successfully',
              ),
            ),
          );
        }
      } else {
        String msg;
        try {
          final body = jsonDecode(res.body);
          msg = (body['error'] ?? body['message'] ?? res.body).toString();
        } catch (_) {
          msg = res.body;
        }
        throw Exception(msg);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Status update failed: $e')),
        );
      }
    }
  }

  List<dynamic> get filteredUsers {
    if (query.trim().isEmpty) return users;

    final q = query.toLowerCase();

    return users.where((u) {
      final name = (u['user_name'] ?? '').toString().toLowerCase();
      final email = (u['user_email'] ?? '').toString().toLowerCase();
      final mobile = (u['user_mobile'] ?? '').toString().toLowerCase();
      final address = (u['user_address'] ?? u['address'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          email.contains(q) ||
          mobile.contains(q) ||
          address.contains(q);
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

  Future<void> showUserDetails(int userId) async {
    try {
      final storage = TokenStorage();
      final token = await storage.getAccessToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token missing. Please login again.');
      }

      final res = await http.get(
        ApiConfig.uri('/api/admin/users/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) throw Exception(res.body);

      final raw = jsonDecode(res.body);
      final data = _mapFrom(raw);
      if (!mounted) return;

      final stats = _mapFrom(data['stats']);
      final user = data.containsKey('user') ? _mapFrom(data['user']) : data;

      final name = _text(user['user_name']);
      final email = _text(user['user_email']);
      final mobile = _text(user['user_mobile']);
      final address = _text(user['user_address'] ?? user['address']);
      final pincode = _text(user['pincode']);
      final status = _text(user['status'], fallback: 'active');

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
                            name.isNotEmpty ? name[0].toUpperCase() : 'U',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                email,
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
                          label: 'Total Orders',
                          value: '${stats['total_orders'] ?? 0}',
                        ),
                        AdminMiniStatTile(
                          label: 'Total Spent',
                          value: '₹${_amount(stats['total_spent'])}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'User Information',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 14),
                    _buildInfoRow('Email', email, icon: Icons.email_outlined),
                    _buildInfoRow('Mobile', mobile, icon: Icons.phone_outlined),
                    _buildInfoRow('Address', address, icon: Icons.location_on_outlined),
                    _buildInfoRow('Pincode', pincode, icon: Icons.pin_drop_outlined),
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
        title: const Text('All Users'),
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
                  labelText: 'Search user (name/email/mobile/address)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredUsers.isEmpty
                  ? const Center(child: Text('No users found'))
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final u = filteredUsers[index];

                  final id = int.tryParse((u['user_id'] ?? '').toString()) ?? 0;
                  final name = (u['user_name'] ?? '').toString();
                  final email = (u['user_email'] ?? '').toString();
                  final mobile = (u['user_mobile'] ?? '').toString();
                  final address = (u['user_address'] ?? u['address'] ?? '').toString();
                  final status = (u['status'] ?? 'active').toString().toLowerCase();

                  final isActive = status == 'active';

                  return AdminItemCard(
                    onTap: id == 0 ? null : () => showUserDetails(id),
                    title: name,
                    lines: [email, mobile, 'Address: $address'],
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
                              isActive ? 'Block User?' : 'Unblock User?',
                            ),
                            content: Text(
                              isActive
                                  ? 'If you block this user, their login and access will be stopped.'
                                  : 'If you unblock this user, their login and access will be restored.',
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
                          await updateUserStatus(id, nextStatus);
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