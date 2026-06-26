import 'package:flutter/material.dart';

import 'package:my_app/screens/token_storage.dart';

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();

    return {
      "Content-Type": "application/json",
      if (token != null) "Authorization": "Bearer $token",
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("About Us")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [

            Text(
              "Shopping App",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            SizedBox(height: 10),

            Text(
              "This app allows users to browse, purchase and manage products easily.\n\n"
                  "Features:\n"
                  "- Easy shopping\n"
                  "- Wishlist\n"
                  "- Secure checkout\n"
                  "- User profile management\n\n"
                  "Developed by: NavGujarat Collage Student",
              style: TextStyle(fontSize: 16),
            ),

          ],
        ),
      ),
    );
  }
}