import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../api_config.dart';
import '../screens/login_page.dart';
import '../screens/token_storage.dart';

class EditSellerProfilePage extends StatefulWidget {
  const EditSellerProfilePage({super.key});

  @override
  State<EditSellerProfilePage> createState() => _EditSellerProfilePageState();
}

class _EditSellerProfilePageState extends State<EditSellerProfilePage> {
  final TextEditingController sellerNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController shopNameController = TextEditingController();
  final TextEditingController shopAddressController = TextEditingController();
  final TextEditingController pincodeController = TextEditingController();
  final TextEditingController licenceController = TextEditingController();

  bool isLoading = true;
  bool isSaving = false;
  String errorMessage = '';
  String? accessToken;

  String currentLogo = '';
  Uint8List? selectedImageBytes;
  String selectedImageName = '';
  bool removeCurrentLogo = false;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    loadTokenAndProfile();
  }

  Future<void> loadTokenAndProfile() async {
    try {
      final storage = TokenStorage();
      accessToken = await storage.getAccessToken();

      if (accessToken == null || accessToken!.isEmpty) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
        return;
      }

      await fetchProfile();
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load token: $e';
        isLoading = false;
      });
    }
  }

  Future<void> fetchProfile() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/api/seller/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final seller = data['seller'];

        setState(() {
          sellerNameController.text = (seller['seller_name'] ?? '').toString();
          emailController.text = (seller['seller_email'] ?? '').toString();
          mobileController.text = (seller['seller_mobile'] ?? '').toString();
          shopNameController.text = (seller['shop_name'] ?? '').toString();
          shopAddressController.text = (seller['shop_address'] ?? '').toString();
          pincodeController.text = (seller['pincode'] ?? '').toString();
          licenceController.text = (seller['licence_no'] ?? '').toString();
          currentLogo = (seller['store_logo'] ?? '').toString();
          removeCurrentLogo = false;
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        final storage = TokenStorage();
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      } else {
        setState(() {
          errorMessage = data['message'] ?? 'Failed to load profile';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  String getCurrentLogoUrl() {
    if (removeCurrentLogo || currentLogo.trim().isEmpty) return '';
    return ApiConfig.fileUrl('/api/seller/logo/$currentLogo');
  }

  Future<void> pickShopLogo() async {
    final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        selectedImageBytes = bytes;
        selectedImageName = pickedFile.name;
        removeCurrentLogo = false;
      });
    }
  }

  void removeShopLogo() {
    setState(() {
      selectedImageBytes = null;
      selectedImageName = '';
      removeCurrentLogo = true;
      currentLogo = '';
    });
  }

  Future<void> updateProfile() async {
    setState(() {
      isSaving = true;
    });

    try {
      final request = http.MultipartRequest(
        'PUT',
        ApiConfig.uri('/api/seller/profile/update'),
      );

      request.headers['Authorization'] = 'Bearer $accessToken';
      request.fields['seller_name'] = sellerNameController.text.trim();
      request.fields['seller_email'] = emailController.text.trim();
      request.fields['seller_mobile'] = mobileController.text.trim();
      request.fields['shop_name'] = shopNameController.text.trim();
      request.fields['shop_address'] = shopAddressController.text.trim();
      request.fields['pincode'] = pincodeController.text.trim();
      request.fields['licence_no'] = licenceController.text.trim();
      request.fields['remove_store_logo'] = removeCurrentLogo ? '1' : '0';

      if (selectedImageBytes != null && selectedImageName.isNotEmpty) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'store_logo',
            selectedImageBytes!,
            filename: selectedImageName,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        Navigator.pop(context, true);
      } else if (response.statusCode == 401 || response.statusCode == 422) {
        final storage = TokenStorage();
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Update failed')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    sellerNameController.dispose();
    emailController.dispose();
    mobileController.dispose();
    shopNameController.dispose();
    shopAddressController.dispose();
    pincodeController.dispose();
    licenceController.dispose();
    super.dispose();
  }

  InputDecoration buildInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLogoUrl = getCurrentLogoUrl();
    final hasAnyImage = selectedImageBytes != null || currentLogoUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2196F3),
        title: const Text(
          'Edit Profile',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Center(
              child: Column(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 55,
                        backgroundColor: const Color(0xFFE3F2FD),
                        backgroundImage: selectedImageBytes != null
                            ? MemoryImage(selectedImageBytes!)
                            : currentLogoUrl.isNotEmpty
                            ? NetworkImage(currentLogoUrl)
                        as ImageProvider
                            : null,
                        child: selectedImageBytes == null &&
                            currentLogoUrl.isEmpty
                            ? const Icon(
                          Icons.store,
                          size: 45,
                          color: Colors.black,
                        )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: InkWell(
                          onTap: pickShopLogo,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2196F3),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              size: 18,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasAnyImage) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: removeShopLogo,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      label: const Text(
                        'Remove Image',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: sellerNameController,
              decoration: buildInputDecoration(
                label: 'Seller Name',
                icon: Icons.person,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: emailController,
              decoration: buildInputDecoration(
                label: 'Email',
                icon: Icons.email,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: mobileController,
              keyboardType: TextInputType.phone,
              decoration: buildInputDecoration(
                label: 'Mobile Number',
                icon: Icons.phone,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: shopNameController,
              decoration: buildInputDecoration(
                label: 'Shop Name',
                icon: Icons.storefront,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: shopAddressController,
              maxLines: 2,
              decoration: buildInputDecoration(
                label: 'Shop Address',
                icon: Icons.location_on,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pincodeController,
              keyboardType: TextInputType.number,
              decoration: buildInputDecoration(
                label: 'Pincode',
                icon: Icons.pin_drop,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: licenceController,
              decoration: buildInputDecoration(
                label: 'Licence Number',
                icon: Icons.badge,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: isSaving ? null : updateProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: isSaving
                    ? const CircularProgressIndicator(
                  color: Colors.white,
                )
                    : const Text(
                  'Save Changes',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}