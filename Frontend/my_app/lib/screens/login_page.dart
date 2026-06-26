import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/admin/dashboard_page.dart';
import 'package:my_app/api_config.dart';
import 'package:my_app/delivery_staff/delivery_staff_home_page.dart';
import 'package:my_app/screens/forgottenPass_page.dart';
import 'package:my_app/screens/register_page.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/seller/seller_home.dart';
import 'package:my_app/user/user_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isPasswordVisible = false;
  bool showContactAdminBox = false;
  bool canContactAdmin = false;
  bool isSendingRequest = false;
  String blockedEmail = '';
  String blockedAccountType = '';
  String infoMessage = '';
  int cooldownRemainingDays = 0;

  final TextEditingController contactMessageController = TextEditingController();

  Future<void> loginUser() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email & password required')),
      );
      return;
    }

    try {
      final response = await http.post(
        ApiConfig.uri('/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': emailController.text.trim(),
          'password': passwordController.text.trim(),
        }),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        final String accessToken = data['access_token'];
        final String refreshToken = data['refresh_token'];
        final String role = data['role'];

        final storage = TokenStorage();
        await storage.saveAccessToken(accessToken);
        await storage.saveRefreshToken(refreshToken);
        await storage.saveRole(role);

        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;

        if (role.toLowerCase() == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DashboardPage()),
          );
        } else if (role.toLowerCase() == 'user') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomePage()),
          );
        } else if (role.toLowerCase() == 'seller') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => SellerHomePage()),
          );
        } else if (role.toLowerCase() == 'delivery_staff') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DeliveryStaffHomePage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Logged in as $role')),
          );
        }
      } else {
        final bool inactiveAccount = data['inactive_account'] == true;

        if (inactiveAccount) {
          setState(() {
            blockedEmail = (data['email'] ?? emailController.text.trim()).toString();
            blockedAccountType = (data['account_type'] ?? '').toString();
            canContactAdmin = data['can_contact_admin'] == true;
            cooldownRemainingDays =
                int.tryParse((data['cooldown_remaining_days'] ?? 0).toString()) ?? 0;
            infoMessage = (data['unblocked_message'] ??
                data['next_request_message'] ??
                data['message'] ??
                'Your account is inactive.')
                .toString();
            showContactAdminBox = true;
          });
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Login failed')),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server not reachable')),
      );
    }
  }

  Future<void> _checkBlockedAccountStatus() async {
    final email = emailController.text.trim();
    if (email.isEmpty) return;

    try {
      final response = await http.post(
        ApiConfig.uri('/api/block-request/check'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          final accountStatus = (data['account_status'] ?? '').toString().toLowerCase();
          blockedEmail = email;
          blockedAccountType = (data['account_type'] ?? '').toString();
          canContactAdmin = data['can_contact_admin'] == true;
          cooldownRemainingDays =
              int.tryParse((data['cooldown_remaining_days'] ?? 0).toString()) ?? 0;
          infoMessage = (data['message'] ?? '').toString();

          showContactAdminBox = accountStatus == 'inactive' || infoMessage.isNotEmpty;
        });
      }
    } catch (_) {}
  }

  Future<void> _sendBlockRequest() async {
    final email = blockedEmail.isNotEmpty
        ? blockedEmail
        : emailController.text.trim();

    final message = contactMessageController.text.trim();

    if (email.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your message first')),
      );
      return;
    }

    setState(() => isSendingRequest = true);

    try {
      final response = await http.post(
        ApiConfig.uri('/api/block-request/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'message': message,
        }),
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (!mounted) return;

      setState(() {
        canContactAdmin = false;
        cooldownRemainingDays =
            int.tryParse((data['cooldown_remaining_days'] ?? 0).toString()) ?? 0;
        infoMessage = (data['message'] ?? 'Request sent successfully').toString();
        if (response.statusCode == 201) {
          contactMessageController.clear();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(infoMessage)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to send request right now')),
      );
    } finally {
      if (mounted) {
        setState(() => isSendingRequest = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    contactMessageController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      prefixIcon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  const Icon(Icons.lock, size: 80, color: Colors.blue),
                  const SizedBox(height: 20),
                  const Text(
                    'Login',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 30),
                  TextField(
                    controller: emailController,
                    decoration: _inputDecoration('Email', Icons.email),
                    onChanged: (_) {
                      if (showContactAdminBox) {
                        setState(() {
                          showContactAdminBox = false;
                          canContactAdmin = false;
                          blockedEmail = '';
                          blockedAccountType = '';
                          infoMessage = '';
                          cooldownRemainingDays = 0;
                        });
                      }
                    },
                    onSubmitted: (_) => _checkBlockedAccountStatus(),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: passwordController,
                    obscureText: !isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            isPasswordVisible = !isPasswordVisible;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: loginUser,
                      child: const Text('Login'),
                    ),
                  ),
                  if (showContactAdminBox) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.deepPurple.shade100),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            infoMessage.isNotEmpty
                                ? infoMessage
                                : 'Your account is inactive.',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (blockedAccountType.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Account type: $blockedAccountType',
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (cooldownRemainingDays > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'You can send another request after $cooldownRemainingDays day(s).',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (canContactAdmin) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: contactMessageController,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'Write your message for admin',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              height: 45,
                              child: ElevatedButton(
                                onPressed: isSendingRequest ? null : _sendBlockRequest,
                                child: isSendingRequest
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : const Text('Contact Admin'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ForgottenpassPage(),
                        ),
                      );
                    },
                    child: const Text('Forgotten password?'),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterPage(),
                          ),
                        );
                      },
                      child: const Text('Create New Account'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}