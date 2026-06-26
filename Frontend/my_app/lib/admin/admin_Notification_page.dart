// UPDATED ADMIN NOTIFICATION PAGE WITH BLOCK REQUESTS
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:my_app/screens/token_storage.dart';

class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  bool notificationsEnabled = true;

  final TextEditingController titleController = TextEditingController();
  final TextEditingController messageController = TextEditingController();

  List requests = [];
  bool loading = false;

  Future<String?> _getToken() async {
    final storage = TokenStorage();
    return await storage.getAccessToken();
  }

  @override
  void initState() {
    super.initState();
    loadRequests();
  }

  Future<void> loadRequests() async {
    setState(() => loading = true);

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Admin token not found. Please login again.')),
          );
        }
        setState(() => loading = false);
        return;
      }

      final response = await http.get(
        ApiConfig.uri('/api/admin/block-requests'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        setState(() {
          requests = jsonDecode(response.body);
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load requests: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Request load error: $e')),
        );
      }
    }

    if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> acceptRequest(int id) async {
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) return;
      final response = await http.put(
        ApiConfig.uri('/api/admin/block-requests/$id/accept'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request accepted successfully')),
          );
        }
        loadRequests();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Accept failed: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Accept error: $e')),
        );
      }
    }
  }

  Future<void> deleteRequest(int id) async {
    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) return;
      final response = await http.delete(
        ApiConfig.uri('/api/admin/block-requests/$id'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Request deleted successfully')),
          );
        }
        loadRequests();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Delete failed: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete error: $e')),
        );
      }
    }
  }

  Future<void> sendNotification() async {
    final title = titleController.text.trim();
    final message = messageController.text.trim();

    if (!notificationsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enable notifications first')),
      );
      return;
    }

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    try {
      final token = await _getToken();
      if (token == null || token.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin token not found. Please login again.')),
        );
        return;
      }

      final response = await http.post(
        ApiConfig.uri('/api/admin/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'title': title,
          'message': message,
          'target_type': 'all',
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification sent successfully')),
        );
        titleController.clear();
        messageController.clear();
      } else {
        String errorMessage = 'Failed to send notification';
        try {
          final body = jsonDecode(response.body);
          errorMessage = (body['message'] ?? body['error'] ?? errorMessage).toString();
        } catch (_) {}

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Notification send error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Admin Notifications")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            SwitchListTile(
              title: const Text("Enable Notifications"),
              value: notificationsEnabled,
              onChanged: (v) => setState(() => notificationsEnabled = v),
            ),

            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Title"),
            ),

            TextField(
              controller: messageController,
              decoration: const InputDecoration(labelText: "Message"),
            ),

            ElevatedButton(
              onPressed: sendNotification,
              child: const Text("Send Notification"),
            ),

            const SizedBox(height: 30),

            const Text(
              "Blocked Requests",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            if (loading)
              const CircularProgressIndicator()
            else if (requests.isEmpty)
              const Text("No requests")
            else
              ...requests.map((r) => Card(
                child: ListTile(
                  title: Text(r['account_name'] ?? ''),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r['email'] ?? ''),
                      Text(r['account_type'] ?? ''),
                      Text(r['message'] ?? ''),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () => acceptRequest(r['request_id']),
                        child: const Text("Accept"),
                      ),
                      const SizedBox(width: 5),
                      ElevatedButton(
                        onPressed: () => deleteRequest(r['request_id']),
                        child: const Text("Delete"),
                      ),
                    ],
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }
}