import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/screens/token_storage.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _allowMultipleAdminLogins = true;
  bool _profileImageRequired = false;

  final TextEditingController _sessionTimeoutController =
  TextEditingController();
  final TextEditingController _maxLoginAttemptsController =
  TextEditingController();
  final TextEditingController _forcePasswordChangeDaysController =
  TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  String get _baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _loadSecuritySettings();
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

  Future<void> _loadSecuritySettings() async {
    setState(() => _isLoading = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token not found');
      }

      final response = await http.get(
        ApiConfig.uri('/api/admin/settings/security'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _allowMultipleAdminLogins =
        data['allow_multiple_admin_logins'] == true ? true : false;
        _profileImageRequired =
        data['profile_image_required'] == true ? true : false;
        _sessionTimeoutController.text =
            (data['session_timeout_minutes'] ?? 15).toString();
        _maxLoginAttemptsController.text =
            (data['max_login_attempts'] ?? 5).toString();
        _forcePasswordChangeDaysController.text =
            (data['force_password_change_days'] ?? 90).toString();
      } else {
        throw Exception(data['message'] ?? 'Failed to load security settings');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load security settings: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSecuritySettings() async {
    FocusScope.of(context).unfocus();

    setState(() => _isSaving = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        throw Exception('Token not found');
      }

      final body = {
        "allow_multiple_admin_logins": _allowMultipleAdminLogins,
        "profile_image_required": _profileImageRequired,
        "session_timeout_minutes":
        int.tryParse(_sessionTimeoutController.text.trim()) ?? 15,
        "max_login_attempts":
        int.tryParse(_maxLoginAttemptsController.text.trim()) ?? 5,
        "force_password_change_days":
        int.tryParse(_forcePasswordChangeDaysController.text.trim()) ?? 90,
      };

      final response = await http.put(
        ApiConfig.uri('/api/admin/settings/security'),
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
        throw Exception(data['message'] ?? 'Failed to save security settings');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save security settings: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _sessionTimeoutController.dispose();
    _maxLoginAttemptsController.dispose();
    _forcePasswordChangeDaysController.dispose();
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
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

  Widget _infoBox(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Settings'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSecuritySettings,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildConstrainedBody([
        _infoBox(
          'This page controls admin side security policies. Change Password will continue to work separately as before.',
        ),
        _sectionCard(
          title: 'Login Control',
          children: [
            _buildSwitchTile(
              title: 'Allow Multiple Admin Logins',
              subtitle:
              'Allow the same admin account to stay logged in on multiple devices',
              value: _allowMultipleAdminLogins,
              onChanged: (value) {
                setState(() => _allowMultipleAdminLogins = value);
              },
            ),
            _buildTextField(
              controller: _maxLoginAttemptsController,
              label: 'Max Login Attempts',
            ),
            _buildTextField(
              controller: _sessionTimeoutController,
              label: 'Session Timeout (Minutes)',
            ),
          ],
        ),
        _sectionCard(
          title: 'Profile and Password Policy',
          children: [
            _buildSwitchTile(
              title: 'Profile Image Required',
              subtitle:
              'Require a profile image for the admin account',
              value: _profileImageRequired,
              onChanged: (value) {
                setState(() => _profileImageRequired = value);
              },
            ),
            _buildTextField(
              controller: _forcePasswordChangeDaysController,
              label: 'Force Password Change After (Days)',
            ),
          ],
        ),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveSecuritySettings,
            icon: _isSaving
                ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
                : const Icon(Icons.save),
            label:
            Text(_isSaving ? 'Saving...' : 'Save Security Settings'),
          ),
        ),
      ]),
    );
  }
}