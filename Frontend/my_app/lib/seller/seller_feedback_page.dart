import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_config.dart';
import '../screens/token_storage.dart';
import '../screens/login_page.dart';

class SellerFeedbackPage extends StatefulWidget {
  const SellerFeedbackPage({super.key});

  @override
  State<SellerFeedbackPage> createState() => _SellerFeedbackPageState();
}

class _SellerFeedbackPageState extends State<SellerFeedbackPage> {
  bool isLoading = true;
  List feedbackList = [];

  @override
  void initState() {
    super.initState();
    fetchFeedback();
  }

  Future<void> fetchFeedback() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();

    if (token == null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
      return;
    }

    try {
      final response = await http.get(
        ApiConfig.uri('/api/seller/feedback'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && mounted) {
        setState(() {
          feedbackList = data['feedback'] ?? [];
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Widget _buildStars(double rating) {
    final rounded = rating.round().clamp(0, 5);

    return Row(
      children: List.generate(
        5,
            (index) => Icon(
          index < rounded ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 18,
        ),
      ),
    );
  }

  Widget buildFeedbackCard(Map item) {
    final double rating =
        double.tryParse((item['rating'] ?? 0).toString()) ?? 0.0;
    final String productName = (item['product_name'] ?? 'Product').toString();
    final String comment = (item['comment'] ?? '').toString().trim();
    final String createdAt = (item['created_at'] ?? '').toString().trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              productName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStars(rating),
                const SizedBox(width: 8),
                Text(
                  rating > 0 ? rating.toStringAsFixed(1) : 'No rating',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              comment.isNotEmpty ? comment : 'No review comment',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            if (createdAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                createdAt,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Feedback"),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : feedbackList.isEmpty
          ? const Center(child: Text("No product feedback available"))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: feedbackList.length,
        itemBuilder: (context, index) {
          return buildFeedbackCard(
            Map<String, dynamic>.from(feedbackList[index]),
          );
        },
      ),
    );
  }
}