import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../screens/token_storage.dart';

class ManagecategoryPage extends StatefulWidget {
  const ManagecategoryPage({super.key});

  @override
  State<ManagecategoryPage> createState() => _ManagecategoryPageState();
}

class _ManagecategoryPageState extends State<ManagecategoryPage> {
  List categories = [];

  final TextEditingController controller = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();

  File? selectedImage;
  Uint8List? webImageBytes;
  String? webImageName;
  bool loading = false;

  String get baseUrl => ApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    fetchCategories();
  }

  Future<String> _getToken() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception("Token missing. Please login again.");
    }
    return token;
  }

  Future fetchCategories() async {
    final response = await http.get(ApiConfig.uri('/api/categories'));
    if (response.statusCode == 200) {
      setState(() {
        categories = jsonDecode(response.body);
      });
    }
  }

  Future pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);

    if (picked != null) {
      if (kIsWeb) {
        webImageBytes = await picked.readAsBytes();
        webImageName = picked.name;
      } else {
        selectedImage = File(picked.path);
      }
      setState(() {});
    }
  }

  void showImagePreview(String imageUrl, String title) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(
            maxWidth: 700,
            maxHeight: 600,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Text("Image not available"),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future addCategory() async {
    if (loading) return;

    if (controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter category name")),
      );
      return;
    }

    if (descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter description")),
      );
      return;
    }

    if (kIsWeb && webImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select image")),
      );
      return;
    }

    if (!kIsWeb && selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select image")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final token = await _getToken();

      var request = http.MultipartRequest(
        "POST",
        ApiConfig.uri('/api/add-category'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['category_name'] = controller.text.trim();
      request.fields['description'] = descriptionController.text.trim();

      if (kIsWeb) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'category_image',
            webImageBytes!,
            filename: webImageName ?? 'category.jpg',
          ),
        );
      } else {
        request.files.add(
          await http.MultipartFile.fromPath(
            'category_image',
            selectedImage!.path,
          ),
        );
      }

      var response = await request.send();
      var respStr = await response.stream.bytesToString();

      Map<String, dynamic> data = {};
      if (respStr.isNotEmpty) {
        try {
          data = jsonDecode(respStr);
        } catch (_) {}
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        controller.clear();
        descriptionController.clear();
        selectedImage = null;
        webImageBytes = null;
        webImageName = null;

        Navigator.pop(context);
        await fetchCategories();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Category Added")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data["error"] ??
                  data["message"] ??
                  "Failed to add category (${response.statusCode})",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future editCategory(int id) async {
    if (loading) return;

    if (controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter category name")),
      );
      return;
    }

    if (descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter description")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final token = await _getToken();

      var request = http.MultipartRequest(
        "PUT",
        ApiConfig.uri('/api/update-category/$id'),
      );

      request.headers['Authorization'] = 'Bearer $token';
      request.fields['category_name'] = controller.text.trim();
      request.fields['description'] = descriptionController.text.trim();

      if (kIsWeb && webImageBytes != null) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'category_image',
            webImageBytes!,
            filename: webImageName ?? 'category.jpg',
          ),
        );
      } else if (!kIsWeb && selectedImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'category_image',
            selectedImage!.path,
          ),
        );
      }

      var response = await request.send();
      var respStr = await response.stream.bytesToString();

      Map<String, dynamic> data = {};
      if (respStr.isNotEmpty) {
        try {
          data = jsonDecode(respStr);
        } catch (_) {}
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        controller.clear();
        descriptionController.clear();
        selectedImage = null;
        webImageBytes = null;
        webImageName = null;

        Navigator.pop(context);
        await fetchCategories();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Category Updated")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data["error"] ??
                  data["message"] ??
                  "Failed to update category (${response.statusCode})",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future deleteCategory(int id) async {
    try {
      final token = await _getToken();

      final response = await http.put(
        ApiConfig.uri('/api/toggle-category/$id'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        await fetchCategories();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Category Deleted")),
        );
      } else {
        Map<String, dynamic> data = {};
        if (response.body.isNotEmpty) {
          try {
            data = jsonDecode(response.body);
          } catch (_) {}
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data["error"] ??
                  data["message"] ??
                  "Failed to delete category (${response.statusCode})",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  void showAddDialog() {
    controller.clear();
    descriptionController.clear();
    selectedImage = null;
    webImageBytes = null;
    webImageName = null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Add Category"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "Enter Category Name",
                ),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  hintText: "Enter Description",
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: pickImage,
                child: const Text("Pick Image"),
              ),
              if (kIsWeb && webImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Image.memory(webImageBytes!, height: 80),
                )
              else if (selectedImage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Image.file(selectedImage!, height: 80),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: addCategory,
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  void showEditDialog(dynamic cat) {
    controller.text = cat['category_name'] ?? "";
    descriptionController.text = cat['description'] ?? "";
    selectedImage = null;
    webImageBytes = null;
    webImageName = null;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Edit Category"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: "Enter Category Name",
                ),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  hintText: "Enter Description",
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: pickImage,
                child: const Text("Replace Image"),
              ),
              if (kIsWeb && webImageBytes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Image.memory(webImageBytes!, height: 80),
                )
              else if (selectedImage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Image.file(selectedImage!, height: 80),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => editCategory(cat['category_id']),
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Manage Categories"),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: showAddDialog,
        child: const Icon(Icons.add),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final cat = categories[index];
          final imageName = (cat['category_image'] ?? '').toString();
          final imageUrl = imageName.isNotEmpty
              ? ApiConfig.fileUrl('uploads/$imageName')
              : '';

          return ListTile(
            leading: imageName.isNotEmpty
                ? GestureDetector(
              onTap: () {
                showImagePreview(
                  imageUrl,
                  (cat['category_name'] ?? 'Category Image')
                      .toString(),
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  imageUrl,
                  width: 45,
                  height: 45,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(Icons.broken_image);
                  },
                ),
              ),
            )
                : const Icon(Icons.category),
            title: Text(cat['category_name'] ?? ""),
            subtitle: Text(cat['description'] ?? ""),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => showEditDialog(cat),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => deleteCategory(cat['category_id']),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}