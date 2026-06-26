import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';

class RateAppPage extends StatefulWidget {
  const RateAppPage({super.key});

  @override
  State<RateAppPage> createState() => _RateAppPageState();
}

Future<Map<String, String>> getHeaders() async {
  final token = await TokenStorage().getAccessToken();
  return {
    "Content-Type": "application/json",
    if (token != null) "Authorization": "Bearer $token",
  };
}

class _RateAppPageState extends State<RateAppPage> {
  int rating = 0;
  bool isSubmitting = false;

  Widget buildStar(int index) {
    return IconButton(
      icon: Icon(
        Icons.star,
        color: index < rating ? Colors.orange : Colors.grey,
        size: 35,
      ),
      onPressed: () {
        setState(() {
          rating = index + 1;
        });
      },
    );
  }

  Future<void> submitRating() async {
    if (rating == 0 || isSubmitting) return;

    setState(() => isSubmitting = true);
    try {
      final response = await http.post(
        ApiConfig.uri('/api/user/rate-app'),
        headers: await getHeaders(),
        body: jsonEncode({"rating": rating}),
      );

      final data = jsonDecode(response.body);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data["message"]?.toString() ??
                (response.statusCode == 200 ? "Rating submitted successfully" : "Failed to submit rating"),
          ),
        ),
      );

      if (response.statusCode == 200) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Rating submit error: $e")),
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Rate App")),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Rate our app", style: TextStyle(fontSize: 20)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) => buildStar(index)),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: rating == 0 || isSubmitting ? null : submitRating,
            child: Text(isSubmitting ? "Submitting..." : "Submit"),
          )
        ],
      ),
    );
  }
}