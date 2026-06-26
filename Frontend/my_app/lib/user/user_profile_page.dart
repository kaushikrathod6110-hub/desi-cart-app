import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_auth_session.dart';
import 'package:my_app/user/user_edit_profile_page.dart';
import 'package:my_app/user/user_home_page.dart';
import 'package:my_app/user/user_my_orders_page.dart';
import 'package:my_app/user/user_rate_app_page.dart';
import 'package:my_app/user/user_settings_page.dart';

import '../screens/login_page.dart';
import 'user_about_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

Future<Map<String, String>> getHeaders() async {
  final token = await TokenStorage().getAccessToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ImagePicker picker = ImagePicker();

  int? userId;
  Uint8List? imageBytes;
  String profileImageUrl = '';
  Map<String, dynamic>? userData;
  bool isLoadingProfile = false;
  bool isSavingImage = false;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<int?> _resolveUserId() async {
    final sessionUserId = await UserAuthSession.getCurrentUserId();
    if (sessionUserId != null && sessionUserId > 0) {
      return sessionUserId;
    }

    final token = await TokenStorage().getAccessToken();
    if (token == null || token.isEmpty) return null;

    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      final rawId = payload['sub'] ?? payload['identity'] ?? payload['user_id'] ?? payload['id'];
      final parsed = rawId == null ? null : int.tryParse(rawId.toString());
      return (parsed != null && parsed > 0) ? parsed : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> loadProfile() async {
    userId = await _resolveUserId();
    if (userId == null) {
      if (mounted) {
        setState(() {
          isLoadingProfile = false;
        });
      }
      return;
    }

    setState(() {
      isLoadingProfile = true;
    });

    try {
      final res = await http.get(
        ApiConfig.uri('/get_user/$userId'),
        headers: await getHeaders(),
      );

      if (res.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body));
        final raw = (data['profile_image_url'] ?? data['profile_image'] ?? '')
            .toString()
            .trim();

        setState(() {
          userData = data;
          imageBytes = null;
          profileImageUrl = raw.isEmpty
              ? ''
              : (raw.startsWith('http://') || raw.startsWith('https://')
              ? raw
              : ApiConfig.fileUrl(raw));
        });
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        isLoadingProfile = false;
      });
    }
  }

  Future<void> _saveProfileImage({Uint8List? bytes, bool remove = false}) async {
    if (userId == null || userData == null || isSavingImage) return;

    setState(() {
      isSavingImage = true;
    });

    try {
      final request = http.MultipartRequest(
        'PUT',
        ApiConfig.uri('/update_user/$userId'),
      );

      final headers = await getHeaders();
      headers.remove('Content-Type');
      request.headers.addAll(headers);

      request.fields['user_name'] = (userData!['user_name'] ?? '').toString();
      request.fields['user_email'] = (userData!['user_email'] ?? '').toString();
      request.fields['user_mobile'] = (userData!['user_mobile'] ?? '').toString();
      request.fields['user_address'] = (userData!['user_address'] ?? '').toString();
      request.fields['pincode'] = (userData!['pincode'] ?? '').toString();
      request.fields['remove_image'] = remove ? '1' : '0';

      if (bytes != null && !remove) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'profile_image',
            bytes,
            filename: 'user_profile.jpg',
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        await loadProfile();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(remove
                ? 'Profile image removed successfully'
                : 'Profile image updated successfully'),
          ),
        );
      } else if (mounted) {
        final data = jsonDecode(response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((data['message'] ?? 'Failed to update image').toString())),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to update profile image')),
        );
      }
    }

    if (mounted) {
      setState(() {
        isSavingImage = false;
      });
    }
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );

    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      imageBytes = bytes;
    });
    await _saveProfileImage(bytes: bytes);
  }

  Future<void> removeImage() async {
    Navigator.pop(context);
    setState(() {
      imageBytes = null;
      profileImageUrl = '';
    });
    await _saveProfileImage(remove: true);
  }

  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () {
                Navigator.pop(context);
                pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('Gallery'),
              onTap: () {
                Navigator.pop(context);
                pickImage(ImageSource.gallery);
              },
            ),
            if (profileImageUrl.isNotEmpty || imageBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Image',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: removeImage,
              ),
          ],
        );
      },
    );
  }

  Widget menuItem(IconData icon, String title, VoidCallback onTap,
      {Color textColor = Colors.black}) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title, style: TextStyle(color: textColor)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildProfileAvatar() {
    if (imageBytes != null) {
      return CircleAvatar(
        radius: 60,
        backgroundColor: Colors.blue.shade100,
        backgroundImage: MemoryImage(imageBytes!),
      );
    }

    if (profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 60,
        backgroundColor: Colors.blue.shade100,
        backgroundImage: NetworkImage(profileImageUrl),
        onBackgroundImageError: (_, __) {
          if (mounted) {
            setState(() {
              profileImageUrl = '';
            });
          }
        },
      );
    }

    return CircleAvatar(
      radius: 60,
      backgroundColor: Colors.blue.shade100,
      child: const Icon(Icons.person, size: 60, color: Colors.blue),
    );
  }

  Widget _infoCard(String label, String value, {IconData? icon}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = (userData?['user_name'] ?? '').toString();
    final email = (userData?['user_email'] ?? '').toString();
    final mobile = (userData?['user_mobile'] ?? '').toString();
    final address = (userData?['user_address'] ?? '').toString();
    final pincode = (userData?['pincode'] ?? '').toString();

    return PopScope(
        canPop: false,
        onPopInvoked: (didPop) {
          if (didPop) return;
          _goToHome();
        },
        child: Scaffold(
          backgroundColor: const Color(0xfff3edf7),
          appBar: AppBar(
            title: const Text('My Profile'),
            backgroundColor: Colors.blue,
            centerTitle: true,
            automaticallyImplyLeading: false,
          ),
          body: RefreshIndicator(
            onRefresh: loadProfile,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      isLoadingProfile ? const CircularProgressIndicator() : _buildProfileAvatar(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    name.isEmpty ? 'User Profile' : name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    email,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ProfilePage()),
                      );
                      await loadProfile();
                    },
                    child: const Text('Edit Profile'),
                  ),
                  const SizedBox(height: 18),
                  _infoCard('Mobile Number', mobile, icon: Icons.phone),
                  _infoCard('Address', address, icon: Icons.home_outlined),
                  _infoCard('Pincode', pincode, icon: Icons.location_on_outlined),
                  const SizedBox(height: 14),
                  menuItem(Icons.settings, 'Settings', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
                    );
                  }),
                  menuItem(Icons.shopping_bag_outlined, 'My Orders', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const UserMyOrdersPage()),
                    );
                  }),
                  menuItem(Icons.star_rate, 'Rate App', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RateAppPage()),
                    );
                  }),
                  menuItem(Icons.info_outline, 'About Us', () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AboutUsPage()),
                    );
                  }),
                  menuItem(Icons.logout, 'Logout', () async {
                    await TokenStorage().deleteTokens();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                    );
                  }, textColor: Colors.red),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ));
  }
}