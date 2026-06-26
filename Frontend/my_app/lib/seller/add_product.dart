import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:my_app/api_config.dart';

import '../screens/login_page.dart';
import '../screens/token_storage.dart';

class AddProductPage extends StatefulWidget {
  const AddProductPage({super.key});

  @override
  State<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<AddProductPage> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile?> _images = List<XFile?>.filled(3, null);
  final List<Uint8List?> _imageBytes = List<Uint8List?>.filled(3, null);

  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  String _selectedUnit = "pcs";

  final List<String> unitOptions = [
    "kg",
    "gm",
    "liter",
    "ml",
    "pcs",
    "dozen"
  ];

  bool _isLoading = false;
  bool _categoriesLoading = true;
  List<Map<String, dynamic>> _categories = [];
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    try {
      final response = await http.get(ApiConfig.uri('/api/categories'));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data is List) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e)),
          );
          _categoriesLoading = false;
        });
      } else {
        setState(() {
          _categoriesLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _categoriesLoading = false;
      });
    }
  }

  int get _selectedCount => _images.where((e) => e != null).length;

  Future<void> _pickImage(int index) async {
    if (_selectedCount >= 3 && _images[index] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You can upload only 3 images.')),
      );
      return;
    }

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _images[index] = image;
        _imageBytes[index] = bytes;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _images[index] = null;
      _imageBytes[index] = null;
    });
  }

  Widget _buildImageBox(int index) {
    final imageBytes = _imageBytes[index];

    return Stack(
      children: [
        GestureDetector(
          onTap: () => _pickImage(index),
          child: Container(
            width: 110,
            height: 110,
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey),
              image: imageBytes != null
                  ? DecorationImage(
                image: MemoryImage(imageBytes),
                fit: BoxFit.cover,
              )
                  : null,
            ),
            child: imageBytes == null
                ? const Icon(Icons.add_a_photo_outlined, size: 30)
                : null,
          ),
        ),
        if (imageBytes != null)
          Positioned(
            right: 12,
            top: 12,
            child: GestureDetector(
              onTap: () => _removeImage(index),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 18),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _addProduct() async {
    final storage = TokenStorage();
    final accessToken = await storage.getAccessToken();

    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    if (_productNameController.text.trim().isEmpty ||
        _selectedCategoryId == null ||
        _priceController.text.trim().isEmpty ||
        _quantityController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        ApiConfig.uri('/api/seller/product/add'),
      );

      request.headers['Authorization'] = 'Bearer $accessToken';
      request.fields['product_name'] = _productNameController.text.trim();
      request.fields['category'] = _selectedCategoryId.toString();
      request.fields['brand'] = _brandController.text.trim();
      request.fields['unit_type'] = _selectedUnit;
      request.fields['price'] = _priceController.text.trim();
      request.fields['quantity'] = _quantityController.text.trim();
      request.fields['stock_available'] = _quantityController.text.trim();
      request.fields['description'] = _descriptionController.text.trim();

      for (int i = 0; i < 3; i++) {
        if (_imageBytes[i] != null && _images[i] != null) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'images',
              _imageBytes[i]!,
              filename: _images[i]!.name,
            ),
          );
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product Added Successfully')),
        );

        _productNameController.clear();
        _priceController.clear();
        _quantityController.clear();
        _descriptionController.clear();

        setState(() {
          for (int i = 0; i < 3; i++) {
            _images[i] = null;
            _imageBytes[i] = null;
          }
          _selectedCategoryId = null;
        });

        if (!mounted) return;
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to add product')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _priceController.dispose();
    _quantityController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  Widget _buildTextField(
      String hint,
      TextEditingController controller, {
        TextInputType keyboardType = TextInputType.text,
        int maxLines = 1,
      }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FA),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF2196F3),
        title: const Text(
          'Add Product',
          style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  const Text(
                    'You can upload only 3 images.',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      _buildImageBox(0),
                      _buildImageBox(1),
                      _buildImageBox(2),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _buildTextField('Product Name', _productNameController),
            const SizedBox(height: 14),
            _categoriesLoading
                ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('Loading categories...'),
            )
                : DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              items: _categories.map((category) {
                return DropdownMenuItem<int>(
                  value: int.tryParse(category['category_id'].toString()),
                  child: Text((category['category_name'] ?? '').toString()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategoryId = value;
                });
              },
              decoration: InputDecoration(
                hintText: 'Category',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 14),

            _buildTextField('Brand', _brandController),

            const SizedBox(height: 14),

            DropdownButtonFormField<String>(
              value: _selectedUnit,
              items: unitOptions.map((unit) {
                return DropdownMenuItem(
                  value: unit,
                  child: Text(unit),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedUnit = value!;
                });
              },
              decoration: InputDecoration(
                hintText: 'Unit Type',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 14),
            _buildTextField('Price', _priceController, keyboardType: TextInputType.number),
            const SizedBox(height: 14),
            _buildTextField('Quantity', _quantityController, keyboardType: TextInputType.number),
            const SizedBox(height: 14),
            _buildTextField('Description', _descriptionController, maxLines: 4),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _addProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'Add Product',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}