import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:my_app/screens/token_storage.dart';

import 'delivery_staff_widgets.dart';
import 'package:my_app/api_config.dart';

class DeliveryStaffEditProfilePage extends StatefulWidget {
  final Map<String, dynamic> initialProfile;
  final Future<void> Function() onProfileUpdated;

  const DeliveryStaffEditProfilePage({
    super.key,
    required this.initialProfile,
    required this.onProfileUpdated,
  });

  @override
  State<DeliveryStaffEditProfilePage> createState() =>
      _DeliveryStaffEditProfilePageState();
}

class _DeliveryStaffEditProfilePageState extends State<DeliveryStaffEditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController nameController;
  late final TextEditingController mobileController;
  late final TextEditingController addressController;
  late final TextEditingController pincodeController;
  late final TextEditingController licenceController;
  late final TextEditingController aadharController;

  String selectedVehicleType = 'Bike';
  bool isSaving = false;
  bool removeCurrentImage = false;
  XFile? pickedImage;
  Uint8List? pickedImageBytes;

  bool get _requiresLicence {
    return selectedVehicleType != 'Cycle' && selectedVehicleType != 'None';
  }

  @override
  void initState() {
    super.initState();
    final profile = widget.initialProfile;
    nameController = TextEditingController(
      text: (profile['delivery_staff_name'] ?? '').toString(),
    );
    mobileController = TextEditingController(
      text: (profile['d_s_mobile'] ?? '').toString(),
    );
    addressController = TextEditingController(
      text: (profile['d_s_address'] ?? '').toString(),
    );
    pincodeController = TextEditingController(
      text: (profile['d_s_pincode'] ?? '').toString(),
    );
    licenceController = TextEditingController(
      text: (profile['staff_licence_no'] ?? '').toString(),
    );
    aadharController = TextEditingController(
      text: (profile['aadhar_card_no'] ?? '').toString(),
    );
    selectedVehicleType = (profile['vehicle_type'] ?? 'Bike').toString();
  }

  @override
  void dispose() {
    nameController.dispose();
    mobileController.dispose();
    addressController.dispose();
    pincodeController.dispose();
    licenceController.dispose();
    aadharController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1200,
    );

    if (file == null) return;

    final Uint8List bytes = await file.readAsBytes();

    setState(() {
      pickedImage = file;
      pickedImageBytes = bytes;
      removeCurrentImage = false;
    });
  }

  void _removeSelectedImage() {
    setState(() {
      pickedImage = null;
      pickedImageBytes = null;
      removeCurrentImage = true;
    });
  }

  Future<void> _showImageOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove Profile Image'),
                onTap: () {
                  Navigator.pop(context);
                  _removeSelectedImage();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _profileAvatar() {
    final imageUrl = imageUrlFromPath(widget.initialProfile['profile_image']);

    if (pickedImageBytes != null) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: MemoryImage(pickedImageBytes!),
      );
    }


    if (!removeCurrentImage && imageUrl != null) {
      return CircleAvatar(
        radius: 48,
        backgroundImage: NetworkImage(imageUrl),
      );
    }

    return CircleAvatar(
      radius: 48,
      backgroundColor: Colors.deepPurple.withOpacity(0.12),
      child: const Icon(
        Icons.person,
        size: 42,
        color: Colors.deepPurple,
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSaving = true);
    try {
      final token = await TokenStorage().getAccessToken();
      if (token == null || token.trim().isEmpty) {
        throw Exception('Login token not found. Please login again');
      }

      final request = http.MultipartRequest(
        'PUT',
        ApiConfig.uri('/api/delivery-staff/profile'),
      );
      request.headers['Authorization'] = 'Bearer $token';

      request.fields['delivery_staff_name'] = nameController.text.trim();
      request.fields['d_s_mobile'] = mobileController.text.trim();
      request.fields['d_s_address'] = addressController.text.trim();
      request.fields['d_s_pincode'] = pincodeController.text.trim();
      request.fields['vehicle_type'] = selectedVehicleType;
      request.fields['staff_licence_no'] = _requiresLicence ? licenceController.text.trim() : '';
      request.fields['aadhar_card_no'] = aadharController.text.trim();
      request.fields['remove_profile_image'] = removeCurrentImage ? '1' : '0';

      if (pickedImage != null) {
        if (kIsWeb) {
          final bytes = pickedImageBytes ?? await pickedImage!.readAsBytes();
          request.files.add(
            http.MultipartFile.fromBytes(
              'profile_image',
              bytes,
              filename: pickedImage!.name,
            ),
          );
        } else {
          request.files.add(
            await http.MultipartFile.fromPath('profile_image', pickedImage!.path),
          );
        }
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();
      final data = body.isNotEmpty ? jsonDecode(body) : {};

      if (response.statusCode == 200) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Profile updated successfully')),
        );
        await widget.onProfileUpdated();
        if (!mounted) return;
        Navigator.pop(context);
      } else {
        throw Exception(data['message'] ?? data['msg'] ?? data['error'] ?? 'Failed to update profile');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Edit Profile'),
        backgroundColor: const Color(0xFFF7F7FB),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              deliverySoftCard(
                child: Column(
                  children: [
                    _profileAvatar(),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _showImageOptions,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Change Profile Image'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              deliverySoftCard(
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: _decoration('Name', Icons.person),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: mobileController,
                      keyboardType: TextInputType.number,
                      decoration: _decoration('Mobile', Icons.phone),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter mobile number';
                        if (v.length != 10 || int.tryParse(v) == null) {
                          return 'Please enter valid 10 digit mobile number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: addressController,
                      maxLines: 2,
                      decoration: _decoration('Address', Icons.home),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: pincodeController,
                      keyboardType: TextInputType.number,
                      decoration: _decoration('Pincode', Icons.pin_drop),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter pincode';
                        if (v.length != 6 || int.tryParse(v) == null) {
                          return 'Please enter valid 6 digit pincode';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedVehicleType,
                      decoration: _decoration('Vehicle Type', Icons.two_wheeler),
                      items: const [
                        DropdownMenuItem(value: 'Bike', child: Text('Bike')),
                        DropdownMenuItem(value: 'Scooter', child: Text('Scooter')),
                        DropdownMenuItem(value: 'Cycle', child: Text('Cycle')),
                        DropdownMenuItem(value: 'None', child: Text('None')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          selectedVehicleType = value ?? 'Bike';
                          if (!_requiresLicence) {
                            licenceController.clear();
                          }
                        });
                      },
                    ),
                    if (_requiresLicence) ...[
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: licenceController,
                        decoration: _decoration('Licence No', Icons.badge),
                        validator: (value) {
                          if (!_requiresLicence) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter licence number';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: aadharController,
                      keyboardType: TextInputType.number,
                      maxLength: 12,
                      decoration: _decoration('Aadhar Card Number', Icons.credit_card),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return 'Please enter Aadhar card number';
                        if (v.length != 12 || int.tryParse(v) == null) {
                          return 'Please enter valid 12 digit Aadhar number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving ? null : _saveProfile,
                        child: isSaving
                            ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}