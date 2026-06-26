import 'dart:convert';

import 'package:my_app/screens/token_storage.dart';

class UserAuthSession {
  static Future<int?> getCurrentUserId() async {
    try {
      final token = await TokenStorage().getAccessToken();
      if (token == null || token.trim().isEmpty) return null;
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final dynamic sub = payload['sub'] ?? payload['identity'] ?? payload['user_id'];
      if (sub == null) return null;
      return int.tryParse(sub.toString());
    } catch (_) {
      return null;
    }
  }
}