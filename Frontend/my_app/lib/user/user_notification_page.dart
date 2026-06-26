import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_order_details_page.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List<dynamic> notifications = [];
  bool isLoading = true;

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    try {
      final response = await http.get(
        ApiConfig.uri('/api/user/notifications'),
        headers: await getHeaders(),
      );

      if (response.statusCode == 200) {
        notifications = jsonDecode(response.body);
        await _markNotificationsAsRead();
      } else {
        notifications = [];
      }
    } catch (_) {
      notifications = [];
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _markNotificationsAsRead() async {
    try {
      await http.post(
        ApiConfig.uri('/api/user/notifications/read-all'),
        headers: await getHeaders(),
      );
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    switch (type.toLowerCase()) {
      case 'admin':
        return Icons.campaign;
      case 'order':
        return Icons.shopping_bag;
      default:
        return Icons.notifications;
    }
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final two = (int value) => value.toString().padLeft(2, '0');
      return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return raw;
    }
  }

  Widget notificationCard(Map<String, dynamic> item) {
    final type = (item['type'] ?? 'notification').toString();
    final createdAt = _formatDate(item['created_at']?.toString());
    final int? orderId = int.tryParse((item['order_id'] ?? '').toString());
    final bool isOrderNotification = type.toLowerCase() == 'order' && orderId != null;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isOrderNotification
            ? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserOrderDetailsPage(orderId: orderId),
            ),
          );
        }
            : null,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: Colors.blue.shade100,
            child: Icon(_iconForType(type), color: Colors.blue),
          ),
          title: Text(
            (item['title'] ?? 'Notification').toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text((item['message'] ?? '').toString()),
                if (isOrderNotification) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Tap to view order details',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ],
                if (createdAt.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    createdAt,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ]
              ],
            ),
          ),
          trailing: isOrderNotification
              ? const Icon(Icons.chevron_right, color: Colors.blue)
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff3edf7),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.blue,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: fetchNotifications,
        child: notifications.isEmpty
            ? ListView(
          children: const [
            SizedBox(height: 160),
            Center(
              child: Text('No notifications available'),
            ),
          ],
        )
            : ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: notifications.length,
          itemBuilder: (context, index) {
            return notificationCard(
              Map<String, dynamic>.from(notifications[index]),
            );
          },
        ),
      ),
    );
  }
}