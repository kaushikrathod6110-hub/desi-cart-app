import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

Future<Map<String, String>> getHeaders() async {
  final token = await TokenStorage().getAccessToken();
  return {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();

  int? userId;
  bool isLoading = true;
  bool isSaving = false;
  Uint8List? selectedImageBytes;
  String profileImageUrl = '';
  bool removeImage = false;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController addressController = TextEditingController();
  final TextEditingController pincodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<int?> _resolveUserId() async {
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

  Future<void> initData() async {
    userId = await _resolveUserId();
    if (userId != null) {
      await fetchUser();
    } else if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchUser() async {
    setState(() {
      isLoading = true;
    });

    final response = await http.get(
      ApiConfig.uri('/get_user/${userId ?? 0}'),
      headers: await getHeaders(),
    );

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(json.decode(response.body));
      setState(() {
        nameController.text = (data['user_name'] ?? '').toString();
        emailController.text = (data['user_email'] ?? '').toString();
        mobileController.text = (data['user_mobile'] ?? '').toString();
        addressController.text = (data['user_address'] ?? '').toString();
        pincodeController.text = (data['pincode'] ?? '').toString();

        final raw = (data['profile_image_url'] ?? data['profile_image'] ?? '').toString().trim();
        profileImageUrl = raw.isEmpty
            ? ''
            : (raw.startsWith('http://') || raw.startsWith('https://')
            ? raw
            : ApiConfig.fileUrl(raw));
        selectedImageBytes = null;
        removeImage = false;
      });
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source, imageQuality: 80);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      selectedImageBytes = bytes;
      removeImage = false;
    });
  }

  Future<void> updateUser() async {
    if (isSaving) return;

    setState(() {
      isSaving = true;
    });

    try {
      final request = http.MultipartRequest(
        'PUT',
        ApiConfig.uri('/update_user/${userId ?? 0}'),
      );

      final headers = await getHeaders();
      headers.remove('Content-Type');
      request.headers.addAll(headers);

      request.fields['user_name'] = nameController.text.trim();
      request.fields['user_email'] = emailController.text.trim();
      request.fields['user_mobile'] = mobileController.text.trim();
      request.fields['user_address'] = addressController.text.trim();
      request.fields['pincode'] = pincodeController.text.trim();
      request.fields['remove_image'] = removeImage ? '1' : '0';

      if (selectedImageBytes != null && !removeImage) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'profile_image',
            selectedImageBytes!,
            filename: 'user_profile.jpg',
          ),
        );
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile Updated Successfully')),
        );
        Navigator.pop(context, true);
      } else {
        dynamic body = {};
        if (response.body.isNotEmpty) {
          try {
            body = jsonDecode(response.body);
          } catch (_) {
            body = {'message': response.body};
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((body['message'] ?? 'Update failed').toString())),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update profile right now: $e')),
      );
    }

    if (mounted) {
      setState(() {
        isSaving = false;
      });
    }
  }

  InputDecoration fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _buildAvatar() {
    if (selectedImageBytes != null) {
      return CircleAvatar(
        radius: 52,
        backgroundColor: Colors.blue.shade100,
        backgroundImage: MemoryImage(selectedImageBytes!),
      );
    }

    if (!removeImage && profileImageUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 52,
        backgroundColor: Colors.blue.shade100,
        backgroundImage: NetworkImage(profileImageUrl),
      );
    }

    return CircleAvatar(
      radius: 52,
      backgroundColor: Colors.blue.shade100,
      child: const Icon(Icons.person, size: 52, color: Colors.blue),
    );
  }

  void _showImageOptions() {
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
            if (selectedImageBytes != null || profileImageUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Remove Image', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    selectedImageBytes = null;
                    profileImageUrl = '';
                    removeImage = true;
                  });
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3edf7),
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: Colors.blue,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                _buildAvatar(),
                GestureDetector(
                  onTap: _showImageOptions,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              decoration: fieldDecoration('Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: mobileController,
              keyboardType: TextInputType.phone,
              decoration: fieldDecoration('Mobile'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: fieldDecoration('Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              maxLines: 2,
              decoration: fieldDecoration('Address'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pincodeController,
              keyboardType: TextInputType.number,
              decoration: fieldDecoration('Pincode'),
            ),
            const SizedBox(height: 25),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: isSaving ? null : updateUser,
                child: isSaving
                    ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
                    : const Text(
                  'Save Changes',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}