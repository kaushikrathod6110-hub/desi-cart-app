import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/screens/token_storage.dart';

class SystemInfoPage extends StatefulWidget {
  const SystemInfoPage({super.key});

  @override
  State<SystemInfoPage> createState() => _SystemInfoPageState();
}

class _SystemInfoPageState extends State<SystemInfoPage> {
  bool _isLoading = true;
  Map<String, dynamic> _data = {};

  String get _baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  Future<String?> _getToken() async {
    final dynamic storage = TokenStorage();
    String? token;

    try {
      token = await storage.getAccessToken() as String?;
    } catch (_) {}

    if (token == null || token.isEmpty) {
      try {
        token = await storage.getToken() as String?;
      } catch (_) {}
    }

    return token;
  }

  Future<void> _loadSystemInfo() async {
    setState(() => _isLoading = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token not found');
      }

      final response = await http.get(
        ApiConfig.uri('/api/admin/system-info'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _data = Map<String, dynamic>.from(data);
      } else {
        throw Exception(data['message'] ?? 'Failed to load system info');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load system info: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  double _getMaxContentWidth(double width) {
    if (width >= 1500) return 1320;
    if (width >= 1200) return 1120;
    if (width >= 900) return 920;
    if (width >= 700) return 760;
    return width;
  }

  EdgeInsets _pagePadding(double width) {
    if (width >= 1200) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    }
    if (width >= 700) {
      return const EdgeInsets.symmetric(horizontal: 18, vertical: 14);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 12);
  }

  int _getCountColumns(double width) {
    if (width >= 1200) return 3;
    if (width >= 700) return 2;
    return 1;
  }

  double _getChildAspectRatio(double width) {
    if (width >= 1200) return 1.75;
    if (width >= 700) return 1.55;
    return 2.2;
  }

  Widget _buildConstrainedBody(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = _getMaxContentWidth(constraints.maxWidth);
        final padding = _pagePadding(constraints.maxWidth);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: EdgeInsets.only(
                left: padding.left,
                right: padding.right,
                top: padding.top,
                bottom: 24,
              ),
              children: children,
            ),
          ),
        );
      },
    );
  }

  Widget _infoCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _rowItem(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isSmall = constraints.maxWidth < 420;

          if (isSmall) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  value == null || value.toString().trim().isEmpty
                      ? '-'
                      : value.toString(),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: Text(
                  value == null || value.toString().trim().isEmpty
                      ? '-'
                      : value.toString(),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _countBox(String title, dynamic count, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.blueGrey.withOpacity(0.08),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 30),
            const SizedBox(height: 10),
            Text(
              count == null ? '0' : count.toString(),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = _data['counts'] is Map ? _data['counts'] as Map : {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Info'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSystemInfo,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildConstrainedBody([
        _infoCard(
          title: 'Application Details',
          children: [
            _rowItem('App Name', _data['app_name']),
            _rowItem('App Version', _data['app_version']),
            _rowItem('Environment', _data['environment']),
            _rowItem('Server Time', _data['server_time']),
            _rowItem('Database Version', _data['database_version']),
            _rowItem('Python Version', _data['python_version']),
          ],
        ),
        _infoCard(
          title: 'Admin Session',
          children: [
            _rowItem('Logged In Admin ID', _data['admin_id']),
            _rowItem('Role', _data['role']),
          ],
        ),
        Card(
          margin: const EdgeInsets.only(bottom: 14),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'System Counts',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: _getCountColumns(width),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      childAspectRatio: _getChildAspectRatio(width),
                      children: [
                        _countBox('Users', counts['users'], Icons.people),
                        _countBox('Sellers', counts['sellers'], Icons.store),
                        _countBox(
                          'Delivery Staff',
                          counts['delivery_staff'],
                          Icons.delivery_dining,
                        ),
                        _countBox(
                          'Categories',
                          counts['categories'],
                          Icons.category,
                        ),
                        _countBox(
                          'Products',
                          counts['products'],
                          Icons.inventory_2,
                        ),
                        _countBox(
                          'Orders',
                          counts['orders'],
                          Icons.receipt_long,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}