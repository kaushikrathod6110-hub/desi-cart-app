import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/admin/Admin_Setting_page.dart';
import 'package:my_app/admin/admin_editProfile_page.dart';
import 'package:my_app/admin/changePassword_page.dart';
import 'package:my_app/screens/token_storage.dart';

import '../screens/login_page.dart';

class AdminMyprofilePage extends StatefulWidget {
  const AdminMyprofilePage({super.key});

  @override
  State<AdminMyprofilePage> createState() => _AdminMyprofilePageState();
}

class _AdminMyprofilePageState extends State<AdminMyprofilePage> {
  String name = '';
  String email = '';
  String mobile = '';
  String profileImageUrl = '';
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    setState(() => isLoading = true);

    try {
      final storage = TokenStorage();
      final String? token = await storage.getAccessToken();

      if (token == null || token.isEmpty) {
        if (!mounted) return;
        setState(() => isLoading = false);
        return;
      }

      final response = await http.get(
        ApiConfig.uri('/api/admin-profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          name = (data['admin_name'] ?? '').toString();
          email = (data['admin_email'] ?? '').toString();
          mobile = (data['admin_mobile'] ?? '').toString();
          profileImageUrl = _normalizeImageUrl((data['profile_image_url'] ?? '').toString());
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  String _normalizeImageUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return ApiConfig.fileUrl(value);
  }

  Widget _buildProfileAvatar() {
    final Widget placeholder = Container(
      color: const Color(0xFFE8DFFF),
      alignment: Alignment.center,
      child: const Icon(Icons.person, size: 60, color: Colors.white),
    );

    final Widget content = profileImageUrl.isNotEmpty
        ? Image.network(
      profileImageUrl,
      fit: BoxFit.cover,
      width: 110,
      height: 110,
      errorBuilder: (_, __, ___) => placeholder,
    )
        : placeholder;

    return Container(
      width: 110,
      height: 110,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(child: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.black),
        ),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 700 ? 700.0 : constraints.maxWidth;
            return Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    children: [
                      const SizedBox(height: 30),
                      _buildProfileAvatar(),
                      const SizedBox(height: 12),
                      isLoading
                          ? const CircularProgressIndicator()
                          : Column(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(email, style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 4),
                          Text(mobile, style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                      const SizedBox(height: 25),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            _profileTile(
                              icon: Icons.edit,
                              title: 'Edit Profile',
                              onTap: () async {
                                final updated = await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const EditProfilePage(),
                                  ),
                                );
                                if (updated == true) {
                                  await loadProfile();
                                }
                              },
                            ),
                            _profileTile(
                              icon: Icons.security,
                              title: 'Change Password',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ChangePasswordPage(),
                                  ),
                                );
                              },
                            ),
                            _profileTile(
                              icon: Icons.settings,
                              title: 'Admin Settings',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => AdminSettingPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () async {
                              final storage = TokenStorage();
                              await storage.deleteTokens();

                              if (!context.mounted) return;
                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(builder: (_) => LoginPage()),
                                    (_) => false,
                              );
                            },
                            child: const Text(
                              'Logout',
                              style: TextStyle(fontSize: 16, color: Colors.red),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _profileTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}