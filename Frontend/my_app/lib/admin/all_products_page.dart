import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;

import '../screens/token_storage.dart';
import 'common/admin_list_widgets.dart';

class AllProductsPage extends StatefulWidget {
  final String? filter;

  const AllProductsPage({super.key, this.filter});

  @override
  State<AllProductsPage> createState() => _AllProductsPageState();
}

class _AllProductsPageState extends State<AllProductsPage> {
  bool isLoading = true;
  bool showOverview = true;

  List<dynamic> products = [];
  String query = '';

  int total = 0;
  int activeAvailable = 0;
  int activeOut = 0;
  int inactiveAvailable = 0;
  int inactiveOut = 0;
  int expiring7d = 0;

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<String> _getToken() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception('Token missing. Please login again.');
    }
    return token;
  }

  String get _pageTitle {
    switch ((widget.filter ?? '').toLowerCase()) {
      case 'out_of_stock':
        return 'Out of Stock Products';
      case 'expiring':
        return 'Expiring Products';
      default:
        return 'All Products';
    }
  }

  String get _emptyMessage {
    switch ((widget.filter ?? '').toLowerCase()) {
      case 'out_of_stock':
        return 'There are no out of stock products.';
      case 'expiring':
        return 'There are no products expiring in the next 7 days.';
      default:
        return 'No products found';
    }
  }

  Future<void> loadAll() async {
    setState(() => isLoading = true);

    try {
      final token = await _getToken();

      final statsRes = await http.get(
        ApiConfig.uri('/api/admin/products/stats'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (statsRes.statusCode != 200) {
        throw Exception(
          'Stats API failed: ${statsRes.statusCode} ${statsRes.body}',
        );
      }
      final stats = jsonDecode(statsRes.body);

      final listRes = await http.get(
        ApiConfig.uri(
          '/api/admin/products',
          queryParameters: {
            if ((widget.filter ?? '').isNotEmpty) 'filter': widget.filter,
          },
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (listRes.statusCode != 200) {
        throw Exception(
          'List API failed: ${listRes.statusCode} ${listRes.body}',
        );
      }
      final list = jsonDecode(listRes.body);

      setState(() {
        total = (stats['total'] ?? 0) as int;
        activeAvailable = (stats['active_available'] ?? 0) as int;
        activeOut = (stats['active_out'] ?? 0) as int;
        inactiveAvailable = (stats['inactive_available'] ?? 0) as int;
        inactiveOut = (stats['inactive_out'] ?? 0) as int;
        expiring7d = (stats['expiring_7d'] ?? 0) as int;
        products = (list is List) ? list : [];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> updateProductStatus(int prodId, String newStatus) async {
    try {
      final token = await _getToken();

      final res = await http.put(
        ApiConfig.uri('/api/admin/products/$prodId/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'prod_status': newStatus}),
      );

      if (res.statusCode == 200) {
        await loadAll();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product status updated to $newStatus')),
          );
        }
      } else {
        String msg;
        try {
          final body = jsonDecode(res.body);
          msg = (body['error'] ?? body['message'] ?? res.body).toString();
        } catch (_) {
          msg = res.body;
        }
        throw Exception(msg);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  List<dynamic> get filteredProducts {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return products;

    return products.where((p) {
      final name = (p['prod_name'] ?? '').toString().toLowerCase();
      final brand = (p['brand'] ?? '').toString().toLowerCase();
      final cat = (p['category_name'] ?? '').toString().toLowerCase();
      final price = (p['prod_price'] ?? '').toString().toLowerCase();
      final rating = (p['avg_rating'] ?? '').toString().toLowerCase();
      final reviews = (p['review_count'] ?? '').toString().toLowerCase();

      return name.contains(q) ||
          brand.contains(q) ||
          cat.contains(q) ||
          price.contains(q) ||
          rating.contains(q) ||
          reviews.contains(q);
    }).toList();
  }

  Widget _buildOverviewSection(List<PieSegment> segments) {
    final active = activeAvailable + activeOut;
    final inactive = inactiveAvailable + inactiveOut;

    Widget statsWrap() {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 10,
        children: [
          Chip(label: Text('Total: $total')),
          Chip(label: Text('Active: $active')),
          Chip(label: Text('Inactive: $inactive')),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Overview',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => showOverview = !showOverview),
                    icon: Icon(
                      showOverview ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    ),
                    label: Text(showOverview ? 'Hide graph' : 'Show graph'),
                  ),
                ],
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 220),
                crossFadeState: showOverview
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: Column(
                  children: [
                    Transform.scale(
                      scale: MediaQuery.of(context).size.width >= 1000 ? 0.88 : 0.82,
                      alignment: Alignment.topCenter,
                      child: AdminResponsiveSection(total: total, segments: segments),
                    ),
                    const SizedBox(height: 8),
                    statsWrap(),
                  ],
                ),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: statsWrap(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showImagePreview(String imageUrl, {String title = 'Image Preview'}) {
    if (!mounted || imageUrl.trim().isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          width: 760,
          height: 620,
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewWidth = constraints.maxWidth;
                    final previewHeight = constraints.maxHeight;

                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: SizedBox(
                        width: previewWidth,
                        height: previewHeight,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Image.network(
                            imageUrl,
                            width: previewWidth,
                            height: previewHeight,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, size: 90),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _pickProductImageUrl(Map<String, dynamic> data) {
    final candidates = [
      data['prod_image_url'],
      data['product_image_url'],
      data['prod_image'],
      data['product_image'],
      data['image'],
    ];

    for (final raw in candidates) {
      final value = (raw ?? '').toString().trim();
      if (value.isEmpty) continue;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }
      return ApiConfig.fileUrl(value.startsWith('uploads/') ? value : 'uploads/$value');
    }
    return '';
  }

  Future<void> showProductDetails(int prodId) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        ApiConfig.uri('/api/admin/products/$prodId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) throw Exception(res.body);
      final data = Map<String, dynamic>.from(jsonDecode(res.body));
      if (!mounted) return;

      final imageUrl = _pickProductImageUrl(data);

      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: 680,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (data['prod_name'] ?? 'Product Details').toString(),
                          style: const TextStyle(
                            fontSize: 20,
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
                  const SizedBox(height: 12),
                  if (imageUrl.isNotEmpty)
                    Center(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showImagePreview(
                          imageUrl,
                          title: (data['prod_name'] ?? 'Product Image').toString(),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl,
                            width: 260,
                            height: 260,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60),
                          ),
                        ),
                      ),
                    ),
                  if (imageUrl.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Center(
                        child: Text(
                          'Tap image to enlarge',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ),
                  if (imageUrl.isNotEmpty) const SizedBox(height: 14),
                  Text('Brand: ${data['brand'] ?? ''}'),
                  const SizedBox(height: 6),
                  Text('Category: ${data['category_name'] ?? ''}'),
                  const SizedBox(height: 6),
                  Text('Seller: ${data['seller_name'] ?? ''}'),
                  const SizedBox(height: 6),
                  Text('Price: ₹${data['prod_price'] ?? 0}'),
                  const SizedBox(height: 6),
                  Text('Average Rating: ${((data['avg_rating'] ?? 0) as num).toStringAsFixed(1)} ⭐ (${data['review_count'] ?? 0} reviews)'),
                  const SizedBox(height: 6),
                  Text('Stock: ${data['stock_quantity'] ?? 0}'),
                  const SizedBox(height: 6),
                  Text('Unit: ${data['unit_type'] ?? ''}'),
                  const SizedBox(height: 6),
                  Text('Status: ${data['prod_status'] ?? ''}'),
                  const SizedBox(height: 6),
                  Text('Stock Status: ${data['stock_status'] ?? ''}'),
                  const SizedBox(height: 6),
                  Text('Expiry: ${data['expiry_at'] ?? '-'}'),
                  const SizedBox(height: 12),
                  Text('Description: ${data['description'] ?? ''}'),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Details error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = [
      PieSegment(label: 'Active-Available', value: activeAvailable),
      PieSegment(label: 'Active-Out', value: activeOut),
      PieSegment(label: 'Inactive-Available', value: inactiveAvailable),
      PieSegment(label: 'Inactive-Out', value: inactiveOut),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle),
        actions: [
          IconButton(
            onPressed: isLoading ? null : loadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildOverviewSection(segments),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search product (name/brand/category/price/rating)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filteredProducts.isEmpty
                  ? Center(child: Text(_emptyMessage))
                  : ListView.builder(
                padding: const EdgeInsets.only(bottom: 16),
                itemCount: filteredProducts.length,
                itemBuilder: (context, index) {
                  final p = filteredProducts[index];

                  final id =
                      int.tryParse((p['prod_id'] ?? '').toString()) ?? 0;
                  final name = (p['prod_name'] ?? '').toString();
                  final brand = (p['brand'] ?? '').toString();
                  final category =
                  (p['category_name'] ?? '—').toString();
                  final price = (p['prod_price'] ?? '').toString();
                  final qty =
                  (p['stock_quantity'] ?? '').toString();
                  final unit = (p['unit_type'] ?? '').toString();
                  final stock =
                  (p['stock_status'] ?? '—').toString();
                  final status =
                  (p['prod_status'] ?? 'Active').toString();

                  final img = (p['prod_image'] ?? '').toString().trim();
                  final imgUrl = img.isEmpty
                      ? null
                      : ApiConfig.fileUrl(
                    img.startsWith('uploads/') ? img : 'uploads/$img',
                  );

                  final isActive = status.toLowerCase() == 'active';

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: id == 0 ? null : () => showProductDetails(id),
                    child: AdminItemCard(
                      leading: imgUrl == null
                          ? const CircleAvatar(
                        radius: 28,
                        child: Icon(Icons.image),
                      )
                          : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          imgUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                          const CircleAvatar(
                            radius: 28,
                            child: Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                      title: name,
                      lines: [
                        'Brand: $brand',
                        'Category: $category',
                        'Price: ₹$price',
                        'Avg Rating: ${(((p['avg_rating'] ?? 0) as num)).toStringAsFixed(1)} ⭐ (${p['review_count'] ?? 0})',
                        'Quantity: $qty | Unit: $unit',
                        'Stock: $stock',
                      ],
                      trailing: StatusActionTrailing(
                        isActive: isActive,
                        activeLabel: 'Active',
                        inactiveLabel: 'Inactive',
                        actionActiveText: 'Disable',
                        actionInactiveText: 'Enable',
                        compact: MediaQuery.of(context).size.width < 700,
                        onPressed: id == 0
                            ? null
                            : () async {
                          final nextStatus =
                          isActive ? 'Inactive' : 'Active';

                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(
                                isActive
                                    ? 'Disable Product?'
                                    : 'Enable Product?',
                              ),
                              content: Text(
                                'Set status to $nextStatus ?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  child: const Text('Yes'),
                                ),
                              ],
                            ),
                          );

                          if (ok == true) {
                            await updateProductStatus(
                              id,
                              nextStatus,
                            );
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}