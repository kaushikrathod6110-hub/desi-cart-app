import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserWishlistService {
  static String _key(int userId) => 'user_wishlist_$userId';

  static Future<Map<String, String>> _getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static int _normalizeSellerId(dynamic sellerId) {
    return int.tryParse((sellerId ?? 0).toString()) ?? 0;
  }

  static Map<String, dynamic> normalizeProduct(Map<String, dynamic> product) {
    final normalized = <String, dynamic>{};
    normalized.addAll(product);

    final dynamic rawImages = product['product_images'] ?? product['prod_images'];
    if (rawImages is List && rawImages.isNotEmpty) {
      normalized['prod_image'] = rawImages.first;
      normalized['prod_images'] = List<dynamic>.from(rawImages);
    }

    normalized['prod_id'] = int.tryParse((product['prod_id'] ?? 0).toString()) ?? 0;
    normalized['prod_name'] = product['prod_name'] ?? '';
    normalized['prod_price'] = product['prod_price'] ?? 0;
    normalized['seller_id'] = _normalizeSellerId(product['seller_id']);
    normalized['seller_name'] = product['seller_name'] ?? '';
    normalized['brand'] = product['brand'] ?? '';
    normalized['description'] = product['description'] ?? '';
    normalized['prod_image'] =
        normalized['prod_image'] ?? product['prod_image'] ?? product['prod_image_url'] ?? '';
    return normalized;
  }

  static Future<List<dynamic>> _readLocal(int? userId) async {
    if (userId == null) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<List<dynamic>> _fetchRemote(int userId) async {
    final response = await http.get(
      ApiConfig.uri('/api/user/wishlist'),
      headers: await _getHeaders(),
    );

    if (response.statusCode != 200) {
      throw Exception('Wishlist fetch failed');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) return [];

    return decoded
        .whereType<Map>()
        .map((e) => normalizeProduct(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> _syncLocalToRemote(int userId, List<dynamic> localItems) async {
    for (final item in localItems) {
      if (item is! Map) continue;
      final product = normalizeProduct(Map<String, dynamic>.from(item));
      final prodId = int.tryParse((product['prod_id'] ?? 0).toString()) ?? 0;
      if (prodId <= 0) continue;

      try {
        await http.post(
          ApiConfig.uri('/api/user/wishlist'),
          headers: await _getHeaders(),
          body: jsonEncode({
            'prod_id': prodId,
            'seller_id': _normalizeSellerId(product['seller_id']),
          }),
        );
      } catch (_) {}
    }
  }

  static Future<List<dynamic>> load(int? userId) async {
    if (userId == null) return [];

    final localItems = await _readLocal(userId);

    try {
      var remoteItems = await _fetchRemote(userId);

      if (remoteItems.isEmpty && localItems.isNotEmpty) {
        await _syncLocalToRemote(userId, localItems);
        remoteItems = await _fetchRemote(userId);
      }

      await save(userId, remoteItems);
      return remoteItems;
    } catch (_) {
      return localItems;
    }
  }

  static Future<void> save(int? userId, List<dynamic> wishlist) async {
    if (userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(userId), jsonEncode(wishlist));
  }

  static bool contains(List<dynamic> wishlist, int prodId, {dynamic sellerId}) {
    final normalizedSellerId = _normalizeSellerId(sellerId);

    return wishlist.any((item) {
      if (item is! Map) return false;
      final sameProd = int.tryParse((item['prod_id'] ?? 0).toString()) == prodId;
      if (!sameProd) return false;

      if (sellerId == null) return true;
      return _normalizeSellerId(item['seller_id']) == normalizedSellerId;
    });
  }

  static Future<List<dynamic>> toggle({
    required int? userId,
    required List<dynamic> wishlist,
    required Map<String, dynamic> product,
  }) async {
    final next = wishlist
        .where((item) => item is Map)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final normalizedProduct = normalizeProduct(product);
    final prodId = int.tryParse((normalizedProduct['prod_id'] ?? 0).toString()) ?? 0;
    final sellerId = _normalizeSellerId(normalizedProduct['seller_id']);

    if (prodId <= 0) {
      await save(userId, next);
      return next;
    }

    final exists = next.any((item) {
      return int.tryParse((item['prod_id'] ?? 0).toString()) == prodId &&
          _normalizeSellerId(item['seller_id']) == sellerId;
    });

    if (userId == null) {
      if (exists) {
        next.removeWhere((item) =>
        int.tryParse((item['prod_id'] ?? 0).toString()) == prodId &&
            _normalizeSellerId(item['seller_id']) == sellerId);
      } else {
        next.add(normalizedProduct);
      }
      await save(userId, next);
      return next;
    }

    try {
      final response = exists
          ? await http.delete(
        ApiConfig.uri('/api/user/wishlist'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'prod_id': prodId,
          'seller_id': sellerId,
        }),
      )
          : await http.post(
        ApiConfig.uri('/api/user/wishlist'),
        headers: await _getHeaders(),
        body: jsonEncode({
          'prod_id': prodId,
          'seller_id': sellerId,
        }),
      );

      if (response.statusCode == 200) {
        final refreshed = await load(userId);
        await save(userId, refreshed);
        return refreshed;
      }
    } catch (_) {}

    if (exists) {
      next.removeWhere((item) =>
      int.tryParse((item['prod_id'] ?? 0).toString()) == prodId &&
          _normalizeSellerId(item['seller_id']) == sellerId);
    } else {
      next.add(normalizedProduct);
    }

    await save(userId, next);
    return next;
  }

  static Future<List<dynamic>> remove({
    required int? userId,
    required List<dynamic> wishlist,
    required int prodId,
    dynamic sellerId,
  }) async {
    final next = wishlist
        .where((item) => item is Map)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    final normalizedSellerId = _normalizeSellerId(sellerId);

    if (userId != null) {
      try {
        final response = await http.delete(
          ApiConfig.uri('/api/user/wishlist'),
          headers: await _getHeaders(),
          body: jsonEncode({
            'prod_id': prodId,
            'seller_id': normalizedSellerId,
          }),
        );

        if (response.statusCode == 200) {
          final refreshed = await load(userId);
          await save(userId, refreshed);
          return refreshed;
        }
      } catch (_) {}
    }

    next.removeWhere((item) {
      final sameProd = int.tryParse((item['prod_id'] ?? 0).toString()) == prodId;
      if (!sameProd) return false;
      return _normalizeSellerId(item['seller_id']) == normalizedSellerId;
    });

    await save(userId, next);
    return next;
  }
}