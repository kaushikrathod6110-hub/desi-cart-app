import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:my_app/api_config.dart';

import '../screens/login_page.dart';
import '../screens/token_storage.dart';
import 'edit_seller_profile.dart';


class SellerProfilePage extends StatefulWidget {
  const SellerProfilePage({super.key});

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  bool isLoading = true;
  String errorMessage = "";
  String? accessToken;
  Map<String, dynamic>? seller;

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
          MaterialPageRoute(builder: (_) => LoginPage()),
        );
        return;
      }

      await fetchSellerProfile();
    } catch (e) {
      setState(() {
        errorMessage = "Failed to load token: $e";
        isLoading = false;
      });
    }
  }

  Future<void> fetchSellerProfile() async {
    try {
      final response = await http.get(
        ApiConfig.uri("/api/seller/profile"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $accessToken",
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["success"] == true) {
        setState(() {
          seller = data["seller"];
          isLoading = false;
        });
      } else if (response.statusCode == 401) {
        final storage = TokenStorage();
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => LoginPage()),
              (route) => false,
        );
      } else {
        setState(() {
          errorMessage = data["message"] ?? "Failed to load profile";
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = "Error: $e";
        isLoading = false;
      });
    }
  }

  String getLogoUrl() {
    final logo = seller?["store_logo"];
    if (logo == null || logo.toString().trim().isEmpty) return "";
    return ApiConfig.fileUrl("/api/seller/logo/$logo");
  }

  Widget profileInfoCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFE3F2FD),
            child: Icon(icon, color: Colors.black),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? "Not Available" : value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = getLogoUrl();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2196F3),
        title: const Text(
          "Seller Profile",
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
          : RefreshIndicator(
        onRefresh: fetchSellerProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: const Color(0xFFE3F2FD),
                      backgroundImage: logoUrl.isNotEmpty
                          ? NetworkImage(logoUrl)
                          : null,
                      child: logoUrl.isEmpty
                          ? const Icon(
                        Icons.store,
                        size: 40,
                        color: Colors.black,
                      )
                          : null,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      (seller?["seller_name"] ?? "").toString(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      (seller?["seller_email"] ?? "").toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              profileInfoCard(
                icon: Icons.phone,
                title: "Mobile Number",
                value: (seller?["seller_mobile"] ?? "").toString(),
              ),
              profileInfoCard(
                icon: Icons.storefront,
                title: "Shop Name",
                value: (seller?["shop_name"] ?? "").toString(),
              ),
              profileInfoCard(
                icon: Icons.location_on,
                title: "Shop Address",
                value: (seller?["shop_address"] ?? "").toString(),
              ),
              profileInfoCard(
                icon: Icons.pin_drop,
                title: "Pincode",
                value: (seller?["pincode"] ?? "").toString(),
              ),
              profileInfoCard(
                icon: Icons.badge,
                title: "Licence Number",
                value: (seller?["licence_no"] ?? "").toString(),
              ),
              profileInfoCard(
                icon: Icons.verified_user,
                title: "Status",
                value: (seller?["status"] ?? "").toString(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EditSellerProfilePage(),
                      ),
                    );

                    if (result == true) {
                      await fetchSellerProfile();
                      if (!mounted) return;
                      Navigator.pop(context, true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Edit Profile",
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
      ),
    );
  }
}