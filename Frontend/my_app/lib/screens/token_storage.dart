import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  final _secureStorage = const FlutterSecureStorage();

  Future<void> saveAccessToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
    } else {
      await _secureStorage.write(key: 'access_token', value: token);
    }
  }

  Future<String?> getAccessToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    } else {
      return await _secureStorage.read(key: 'access_token');
    }
  }

  // ================= REFRESH TOKEN =================

  Future<void> saveRefreshToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('refresh_token', token);
    } else {
      await _secureStorage.write(key: 'refresh_token', value: token);
    }
  }

  Future<String?> getRefreshToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('refresh_token');
    } else {
      return await _secureStorage.read(key: 'refresh_token');
    }
  }

  // ================= DELETE BOTH =================

  Future<void> deleteTokens() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_role');
    } else {
      await _secureStorage.delete(key: 'access_token');
      await _secureStorage.delete(key: 'refresh_token');
      await _secureStorage.delete(key: 'user_role');

    }
  }

  Future<void> saveRole(String role) async {
    if(kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
    }
    else {
      await _secureStorage.write(key: 'user_role', value: role);
    }
  }

  Future<String?> getRole() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_role');
    } else {
      return await _secureStorage.read(key: 'user_role');
    }
  }
}