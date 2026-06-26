import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/screens/token_storage.dart';

class AppConfigurationPage extends StatefulWidget {
  const AppConfigurationPage({super.key});

  @override
  State<AppConfigurationPage> createState() => _AppConfigurationPageState();
}

class _AppConfigurationPageState extends State<AppConfigurationPage> {
  final TextEditingController _appNameController = TextEditingController();
  final TextEditingController _supportEmailController = TextEditingController();
  final TextEditingController _supportMobileController = TextEditingController();
  final TextEditingController _currencyController = TextEditingController();
  final TextEditingController _currencySymbolController =
  TextEditingController();
  final TextEditingController _lowStockThresholdController =
  TextEditingController();

  bool _newOrderNotifications = true;
  bool _deliveryAlertNotifications = true;
  bool _maintenanceMode = false;

  bool _isLoading = true;
  bool _isSaving = false;

  String get _baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadConfig();
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

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception("Token not found");
      }

      final response = await http.get(
        ApiConfig.uri('/api/admin/settings/app-configuration'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _appNameController.text = (data['app_name'] ?? '').toString();
        _supportEmailController.text = (data['support_email'] ?? '').toString();
        _supportMobileController.text =
            (data['support_mobile'] ?? '').toString();
        _currencyController.text = (data['currency'] ?? '').toString();
        _currencySymbolController.text =
            (data['currency_symbol'] ?? '').toString();
        _lowStockThresholdController.text =
            (data['low_stock_threshold'] ?? 5).toString();

        _newOrderNotifications =
        data['new_order_notifications'] == true ? true : false;
        _deliveryAlertNotifications =
        data['delivery_alert_notifications'] == true ? true : false;
        _maintenanceMode = data['maintenance_mode'] == true ? true : false;
      } else {
        throw Exception(data['message'] ?? 'Failed to load configuration');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load app configuration: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    FocusScope.of(context).unfocus();

    if (_appNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App name is required')),
      );
      return;
    }

    if (_currencyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Currency is required')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception("Token not found");
      }

      final body = {
        "app_name": _appNameController.text.trim(),
        "support_email": _supportEmailController.text.trim(),
        "support_mobile": _supportMobileController.text.trim(),
        "currency": _currencyController.text.trim(),
        "currency_symbol": _currencySymbolController.text.trim(),
        "low_stock_threshold":
        int.tryParse(_lowStockThresholdController.text.trim()) ?? 5,
        "new_order_notifications": _newOrderNotifications,
        "delivery_alert_notifications": _deliveryAlertNotifications,
        "maintenance_mode": _maintenanceMode,
      };

      final response = await http.put(
        ApiConfig.uri('/api/admin/settings/app-configuration'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Saved successfully')),
          );
        }
      } else {
        throw Exception(data['message'] ?? 'Failed to save configuration');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save configuration: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _appNameController.dispose();
    _supportEmailController.dispose();
    _supportMobileController.dispose();
    _currencyController.dispose();
    _currencySymbolController.dispose();
    _lowStockThresholdController.dispose();
    super.dispose();
  }

  double _getMaxContentWidth(double width) {
    if (width >= 1400) return 1100;
    if (width >= 1000) return 920;
    if (width >= 700) return 760;
    return width;
  }

  EdgeInsets _pagePadding(double width) {
    if (width >= 1000) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 16);
    }
    if (width >= 700) {
      return const EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 12);
  }

  Widget _buildConstrainedBody(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = _getMaxContentWidth(constraints.maxWidth);

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: ListView(
              padding: EdgeInsets.only(
                left: _pagePadding(constraints.maxWidth).left,
                right: _pagePadding(constraints.maxWidth).right,
                top: _pagePadding(constraints.maxWidth).top,
                bottom: 24,
              ),
              children: children,
            ),
          ),
        );
      },
    );
  }

  Widget _sectionCard({
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
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('App Configuration'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadConfig,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildConstrainedBody([
        _sectionCard(
          title: 'General',
          children: [
            _buildTextField(
              controller: _appNameController,
              label: 'App Name',
            ),
            _buildTextField(
              controller: _supportEmailController,
              label: 'Support Email',
              keyboardType: TextInputType.emailAddress,
            ),
            _buildTextField(
              controller: _supportMobileController,
              label: 'Support Mobile',
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        _sectionCard(
          title: 'Business Settings',
          children: [
            _buildTextField(
              controller: _currencyController,
              label: 'Currency',
            ),
            _buildTextField(
              controller: _currencySymbolController,
              label: 'Currency Symbol',
            ),
            _buildTextField(
              controller: _lowStockThresholdController,
              label: 'Low Stock Threshold',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        _sectionCard(
          title: 'Operational Controls',
          children: [
            _buildSwitchTile(
              title: 'New Order Notifications',
              subtitle: 'Show alerts when a new order is placed',
              value: _newOrderNotifications,
              onChanged: (value) {
                setState(() => _newOrderNotifications = value);
              },
            ),
            _buildSwitchTile(
              title: 'Delivery Alert Notifications',
              subtitle: 'Show alerts for delivery related updates',
              value: _deliveryAlertNotifications,
              onChanged: (value) {
                setState(() => _deliveryAlertNotifications = value);
              },
            ),
            _buildSwitchTile(
              title: 'Maintenance Mode',
              subtitle: 'Temporarily put the app into maintenance mode',
              value: _maintenanceMode,
              onChanged: (value) {
                setState(() => _maintenanceMode = value);
              },
            ),
          ],
        ),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveConfig,
            icon: _isSaving
                ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Configuration'),
          ),
        ),
      ]),
    );
  }
}