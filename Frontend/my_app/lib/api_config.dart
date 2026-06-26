import 'package:flutter/foundation.dart';
import 'package:my_app/api_config.dart';

class ApiConfig {
  static const String _webBaseUrl = 'http://localhost:5000';
  static const String _mobileHost = 'http://10.73.214.167';

  static String get baseUrl {
    if (kIsWeb) return _webBaseUrl;
    return _mobileHost.contains(RegExp(r':\d+$')) ? _mobileHost : '$_mobileHost:5000';
  }

  static Uri uri(String path, {Map<String, dynamic>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: normalizedPath,
      queryParameters: queryParameters?.map(
            (key, value) => MapEntry(key, value?.toString()),
      ),
    );
  }

  static String fileUrl(String relativePath) {
    final cleaned = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return '$baseUrl/$cleaned';
  }
}