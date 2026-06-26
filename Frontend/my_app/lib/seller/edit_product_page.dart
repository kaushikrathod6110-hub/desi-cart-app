import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:my_app/api_config.dart';

import '../screens/login_page.dart';
import '../screens/token_storage.dart';

class EditProductPage extends StatefulWidget {
  final Map<String, dynamic> product;

  const EditProductPage({super.key, required this.product});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  late TextEditingController nameController;
  late TextEditingController priceController;
  late TextEditingController stockController;

  final ImagePicker _picker = ImagePicker();
  final List<Uint8List?> _pickedImageBytes = List<Uint8List?>.filled(3, null);
  final List<String> _pickedImageNames = List<String>.filled(3, '');
  late List<String> _existingImageUrls;

  final int lowStockLimit = 5;
  final List<String> _unitOptions = const [
    'kg',
    'gm',
    'liter',
    'ml',
    'pcs',
    'dozen',
  ];

  bool isSaving = false;
  String? accessToken;
  bool categoriesLoading = true;
  List<Map<String, dynamic>> categories = [];
  int? selectedCategoryId;
  String? selectedUnit;

  @override
  void initState() {
    super.initState();
    nameController =
        TextEditingController(text: widget.product['name']?.toString() ?? '');
    priceController =
        TextEditingController(text: widget.product['price']?.toString() ?? '');
    stockController =
        TextEditingController(text: widget.product['stock']?.toString() ?? '');
    selectedUnit = (widget.product['unit'] ?? '').toString().trim().isEmpty
        ? 'pcs'
        : widget.product['unit'].toString().trim();
    selectedCategoryId = int.tryParse(
      (widget.product['category_id'] ?? '').toString(),
    );

    _existingImageUrls = _extractExistingImages();

    loadToken();
    fetchCategories();
  }

  List<String> _extractExistingImages() {
    final images = <String>[];

    final list = widget.product['images'];
    if (list is List) {
      for (final item in list) {
        final value = (item ?? '').toString().trim();
        if (value.isNotEmpty) {
          images.add(value);
        }
      }
    }

    for (final key in ['prod_image_url', 'prod_image2_url', 'prod_image3_url', 'image']) {
      final value = (widget.product[key] ?? '').toString().trim();
      if (value.isNotEmpty && !images.contains(value)) {
        if (value.startsWith('http://') || value.startsWith('https://')) {
          images.add(value);
        } else if (value.startsWith('/')) {
          images.add(ApiConfig.fileUrl(value));
        } else if (value.contains('uploads/')) {
          images.add(ApiConfig.fileUrl('/$value'));
        }
      }
    }

    while (images.length < 3) {
      images.add('');
    }
    return images.take(3).toList();
  }

  Future<void> loadToken() async {
    final storage = TokenStorage();
    accessToken = await storage.getAccessToken();
  }

  Future<void> fetchCategories() async {
    try {
      final response = await http.get(ApiConfig.uri('/api/categories'));
      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data is List) {
        setState(() {
          categories = List<Map<String, dynamic>>.from(
            data.map((e) => Map<String, dynamic>.from(e)),
          );
          if (selectedCategoryId == null && categories.isNotEmpty) {
            selectedCategoryId =
                int.tryParse(categories.first['category_id'].toString());
          }
          categoriesLoading = false;
        });
      } else {
        setState(() {
          categoriesLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        categoriesLoading = false;
      });
    }
  }

  Future<void> pickImage(int index) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final bytes = await image.readAsBytes();
      setState(() {
        _pickedImageBytes[index] = bytes;
        _pickedImageNames[index] = image.name;
      });
    }
  }

  ImageProvider? _buildImageProvider(int index) {
    if (_pickedImageBytes[index] != null) {
      return MemoryImage(_pickedImageBytes[index]!);
    }

    final imagePath = _existingImageUrls[index];
    if (imagePath.trim().isEmpty) {
      return null;
    }

    if (imagePath.startsWith('http://') || imagePath.startsWith('https://')) {
      return NetworkImage(imagePath);
    }

    if (imagePath.startsWith('/')) {
      return NetworkImage(ApiConfig.fileUrl(imagePath));
    }

    if (imagePath.contains('uploads/')) {
      return NetworkImage(ApiConfig.fileUrl('/$imagePath'));
    }

    return null;
  }

  Future<void> saveProduct() async {
    final prodId = widget.product['prod_id'] ?? widget.product['id'];

    if (prodId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product ID not found')),
      );
      return;
    }

    if (nameController.text.trim().isEmpty ||
        selectedCategoryId == null ||
        priceController.text.trim().isEmpty ||
        stockController.text.trim().isEmpty ||
        selectedUnit == null ||
        selectedUnit!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    if (accessToken == null || accessToken!.isEmpty) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
            (route) => false,
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    try {
      final request = http.MultipartRequest(
        'PUT',
        ApiConfig.uri('/api/seller/product/update/$prodId'),
      );

      request.headers['Authorization'] = 'Bearer $accessToken';
      request.fields['name'] = nameController.text.trim();
      request.fields['category'] = selectedCategoryId.toString();
      request.fields['price'] = priceController.text.trim();
      request.fields['stock'] = stockController.text.trim();
      request.fields['unit'] = selectedUnit!;
      request.fields['description'] =
          (widget.product['description'] ?? '').toString();

      for (int i = 0; i < 3; i++) {
        if (_pickedImageBytes[i] != null && _pickedImageNames[i].isNotEmpty) {
          request.files.add(
            http.MultipartFile.fromBytes(
              'image${i + 1}',
              _pickedImageBytes[i]!,
              filename: _pickedImageNames[i],
            ),
          );
        }
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && data['success'] == true) {
        final product = data['product'] ?? {};

        final updatedProduct = {
          'prod_id': product['prod_id'] ?? prodId,
          'id': product['prod_id'] ?? prodId,
          'name': product['prod_name'] ?? nameController.text.trim(),
          'price': product['prod_price'] ?? priceController.text.trim(),
          'stock': product['stock_quantity'] ?? stockController.text.trim(),
          'unit': product['unit_type'] ?? selectedUnit!,
          'category_id': product['category_id'] ?? selectedCategoryId,
          'images': product['images'] ??
              [
                product['prod_image_url'],
                product['prod_image2_url'],
                product['prod_image3_url'],
              ].where((e) => e != null && e.toString().isNotEmpty).toList(),
          'prod_image_url': product['prod_image_url'],
          'prod_image2_url': product['prod_image2_url'],
          'prod_image3_url': product['prod_image3_url'],
        };

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Product updated successfully'),
          ),
        );
        Navigator.pop(context, updatedProduct);
      } else if (response.statusCode == 401 || response.statusCode == 422) {
        final storage = TokenStorage();
        await storage.deleteTokens();

        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data['message'] ?? 'Failed to update product'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }

  Widget _buildImageBox(int index) {
    final imageProvider = _buildImageProvider(index);

    return Container(
      width: 110,
      margin: const EdgeInsets.all(8),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => pickImage(index),
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
                image: imageProvider != null
                    ? DecorationImage(
                  image: imageProvider,
                  fit: BoxFit.cover,
                )
                    : null,
              ),
              child: imageProvider == null
                  ? const Icon(Icons.add_a_photo_outlined, size: 30)
                  : null,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            imageProvider == null ? 'Add Image' : 'Tap to change',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    priceController.dispose();
    stockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int stock =
        int.tryParse(stockController.text) ??
            (widget.product['stock'] is num
                ? (widget.product['stock'] as num).toInt()
                : int.tryParse((widget.product['stock'] ?? '0').toString()) ?? 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Product'),
        backgroundColor: const Color(0xFF2196F3),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stock <= lowStockLimit)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Low stock! Please refill this product.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
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
            const SizedBox(height: 24),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Product Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            categoriesLoading
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<int>(
              value: selectedCategoryId,
              items: categories.map((category) {
                return DropdownMenuItem<int>(
                  value: int.tryParse(category['category_id'].toString()),
                  child: Text((category['category_name'] ?? '').toString()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedCategoryId = value;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Price (₹)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: stockController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Stock Quantity',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _unitOptions.contains(selectedUnit) ? selectedUnit : 'pcs',
              items: _unitOptions.map((unit) {
                return DropdownMenuItem<String>(
                  value: unit,
                  child: Text(unit),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedUnit = value;
                });
              },
              decoration: const InputDecoration(
                labelText: 'Unit Type',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isSaving ? null : saveProduct,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2196F3),
                ),
                child: Text(
                  isSaving ? 'Saving...' : 'Save Changes',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}