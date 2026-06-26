import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/login_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController shopNameController = TextEditingController();
  final TextEditingController shopAddressController = TextEditingController();
  final TextEditingController deliveryAddressController = TextEditingController();
  final TextEditingController deliveryPincodeController = TextEditingController();
  final TextEditingController licenceController = TextEditingController();
  final TextEditingController aadharController = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  String selectedRole = 'user';
  String selectedVehicleType = 'Bike';
  bool isPasswordVisible = false;
  bool isLoading = false;

  bool get _requiresLicence {
    return selectedRole == 'delivery_staff' &&
        selectedVehicleType != 'Cycle' &&
        selectedVehicleType != 'None';
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    passwordController.dispose();
    shopNameController.dispose();
    shopAddressController.dispose();
    deliveryAddressController.dispose();
    deliveryPincodeController.dispose();
    licenceController.dispose();
    aadharController.dispose();
    super.dispose();
  }

  void _clearConditionalFields() {
    shopNameController.clear();
    shopAddressController.clear();
    deliveryAddressController.clear();
    deliveryPincodeController.clear();
    licenceController.clear();
    aadharController.clear();
    selectedVehicleType = 'Bike';
  }

  void _handleVehicleTypeChange(String? value) {
    setState(() {
      selectedVehicleType = value ?? 'Bike';
      if (!_requiresLicence) {
        licenceController.clear();
      }
    });
  }

  Future<void> registerUser() async {
    final response = await http.post(
      ApiConfig.uri('/register/user'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user_name': nameController.text.trim(),
        'user_email': emailController.text.trim(),
        'user_mobile': phoneController.text.trim(),
        'user_pass': passwordController.text.trim(),
      }),
    );

    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

    if (response.statusCode == 201) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User Registered')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
      );
    } else {
      throw Exception(data['message'] ?? 'Registration Failed');
    }
  }

  Future<void> registerSeller() async {
    final response = await http.post(
      ApiConfig.uri('/register/seller'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'seller_name': nameController.text.trim(),
        'seller_email': emailController.text.trim(),
        'seller_mobile': phoneController.text.trim(),
        'shop_name': shopNameController.text.trim(),
        'shop_address': shopAddressController.text.trim(),
        'seller_pass': passwordController.text.trim(),
      }),
    );

    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

    if (response.statusCode == 201) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seller Registered')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
      );
    } else {
      throw Exception(data['message'] ?? 'Registration Failed');
    }
  }

  Future<void> registerDeliveryStaff() async {
    final response = await http.post(
      ApiConfig.uri('/register/delivery-staff'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'delivery_staff_name': nameController.text.trim(),
        'd_s_email': emailController.text.trim(),
        'd_s_mobile': phoneController.text.trim(),
        'd_s_pass': passwordController.text.trim(),
        'd_s_address': deliveryAddressController.text.trim(),
        'd_s_pincode': deliveryPincodeController.text.trim(),
        'vehicle_type': selectedVehicleType,
        'staff_licence_no': _requiresLicence ? licenceController.text.trim() : '',
        'aadhar_card_no': aadharController.text.trim(),
      }),
    );

    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

    if (response.statusCode == 201) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery Staff Registered')),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (_) => false,
      );
    } else {
      throw Exception(data['message'] ?? 'Registration Failed');
    }
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
    final bool isSeller = selectedRole == 'seller';
    final bool isDelivery = selectedRole == 'delivery_staff';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Account',
          style: TextStyle(fontSize: 26),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: _inputDecoration(
                        isDelivery ? 'Delivery Staff Name' : 'Full Name',
                        Icons.person,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration('Phone No', Icons.phone),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter mobile number';
                        if (v.length != 10 || int.tryParse(v) == null) {
                          return 'Please enter valid 10 digit mobile number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      controller: emailController,
                      decoration: _inputDecoration('Email', Icons.email),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter email';
                        if (!v.contains('@')) return 'Please enter valid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
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
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter password';
                        if (v.length < 6) {
                          return 'Please enter at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          const Text(
                            'Select Your Type :',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          RadioMenuButton<String>(
                            value: 'user',
                            groupValue: selectedRole,
                            onChanged: (value) {
                              setState(() {
                                selectedRole = value!;
                                _clearConditionalFields();
                              });
                            },
                            child: const Text('User'),
                          ),
                          RadioMenuButton<String>(
                            value: 'seller',
                            groupValue: selectedRole,
                            onChanged: (value) {
                              setState(() {
                                selectedRole = value!;
                                _clearConditionalFields();
                              });
                            },
                            child: const Text('Seller'),
                          ),
                          RadioMenuButton<String>(
                            value: 'delivery_staff',
                            groupValue: selectedRole,
                            onChanged: (value) {
                              setState(() {
                                selectedRole = value!;
                                _clearConditionalFields();
                              });
                            },
                            child: const Text('Delivery Staff'),
                          ),
                        ],
                      ),
                    ),
                    if (isSeller) ...[
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: shopNameController,
                        decoration: _inputDecoration('Shop Name', Icons.store),
                        validator: (value) {
                          if (!isSeller) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter shop name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: shopAddressController,
                        maxLines: 2,
                        decoration: _inputDecoration(
                          'Shop Address',
                          Icons.location_on,
                        ),
                        validator: (value) {
                          if (!isSeller) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter shop address';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (isDelivery) ...[
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: deliveryAddressController,
                        maxLines: 2,
                        decoration: _inputDecoration('Address', Icons.home),
                        validator: (value) {
                          if (!isDelivery) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter address';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: deliveryPincodeController,
                        keyboardType: TextInputType.number,
                        decoration: _inputDecoration('Pincode', Icons.pin_drop),
                        validator: (value) {
                          if (!isDelivery) return null;
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) return 'Please enter pincode';
                          if (v.length != 6 || int.tryParse(v) == null) {
                            return 'Please enter valid 6 digit pincode';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),
                      DropdownButtonFormField<String>(
                        value: selectedVehicleType,
                        decoration: _inputDecoration(
                          'Vehicle Type',
                          Icons.two_wheeler,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Bike', child: Text('Bike')),
                          DropdownMenuItem(
                            value: 'Scooter',
                            child: Text('Scooter'),
                          ),
                          DropdownMenuItem(value: 'Cycle', child: Text('Cycle')),
                          DropdownMenuItem(value: 'None', child: Text('None')),
                        ],
                        onChanged: _handleVehicleTypeChange,
                      ),
                      const SizedBox(height: 15),
                      if (_requiresLicence)
                        TextFormField(
                          controller: licenceController,
                          decoration: _inputDecoration('Licence No', Icons.badge),
                          validator: (value) {
                            if (!_requiresLicence) return null;
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter licence number';
                            }
                            return null;
                          },
                        ),
                      if (_requiresLicence) const SizedBox(height: 15),
                      TextFormField(
                        controller: aadharController,
                        keyboardType: TextInputType.number,
                        maxLength: 12,
                        decoration: _inputDecoration(
                          'Aadhar Card Number',
                          Icons.credit_card,
                        ),
                        validator: (value) {
                          if (!isDelivery) return null;
                          final v = value?.trim() ?? '';
                          if (v.isEmpty) {
                            return 'Please enter Aadhar card number';
                          }
                          if (v.length != 12 || int.tryParse(v) == null) {
                            return 'Please enter valid 12 digit Aadhar number';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (isLoading) return;
                          if (_formKey.currentState!.validate()) {
                            setState(() => isLoading = true);
                            try {
                              if (selectedRole == 'user') {
                                await registerUser();
                              } else if (selectedRole == 'seller') {
                                await registerSeller();
                              } else {
                                await registerDeliveryStaff();
                              }
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e.toString().replaceFirst('Exception: ', ''),
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => isLoading = false);
                              }
                            }
                          }
                        },
                        child: isLoading
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : const Text('Register'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}