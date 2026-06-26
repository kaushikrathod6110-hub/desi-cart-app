import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/otpVerification_page.dart';

class ForgottenpassPage extends StatefulWidget {
  const ForgottenpassPage({super.key});

  @override
  State<ForgottenpassPage> createState() => _ForgottenpassPageState();
}

class _ForgottenpassPageState extends State<ForgottenpassPage> {
  final TextEditingController controller = TextEditingController();
  bool isEmail = true;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final value = controller.text.trim();

    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Field cannot be empty')),
      );
      return;
    }

    final response = await http.post(
      ApiConfig.uri('/api/check-account'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(isEmail ? {'email': value} : {'mobile': value}),
    );

    if (response.statusCode == 200) {
      final otpResponse = await http.post(
        ApiConfig.uri('/api/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': value}),
      );

      if (otpResponse.statusCode == 200) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpverificationPage(email: value),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send OTP')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEmail ? 'Email address not match' : 'Mobile number not match',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Find your account',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isEmail
                        ? 'Enter your email address.'
                        : 'Enter your mobile number.',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    keyboardType: isEmail
                        ? TextInputType.emailAddress
                        : TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: isEmail ? 'Email address' : 'Mobile number',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _continue,
                      child: const Text('Continue'),
                    ),
                  ),
                  const SizedBox(height: 30),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          isEmail = !isEmail;
                          controller.clear();
                        });
                      },
                      child: Text(
                        isEmail
                            ? 'Find by mobile number'
                            : 'Find by email address',
                      ),
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