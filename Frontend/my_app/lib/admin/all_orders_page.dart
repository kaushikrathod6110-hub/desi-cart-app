
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/token_storage.dart';
import '../api_config.dart';
import 'common/admin_list_widgets.dart';

class AllOrdersPage extends StatefulWidget {
  final String? filter;

  const AllOrdersPage({super.key, this.filter});

  @override
  State<AllOrdersPage> createState() => _AllOrdersPageState();
}

class _AllOrdersPageState extends State<AllOrdersPage> {
  bool isLoading = true;
  bool showOverview = true;

  List<dynamic> orders = [];
  String query = '';

  int total = 0;
  int pending = 0;
  int confirmed = 0;
  int packed = 0;
  int outForDelivery = 0;
  int delivered = 0;

  int paid = 0;
  int payPending = 0;
  int failed = 0;

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

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  String _formatAmount(dynamic value) {
    if (value == null) return '0.00';
    if (value is num) return value.toStringAsFixed(2);
    final parsed = double.tryParse(value.toString()) ?? 0;
    return parsed.toStringAsFixed(2);
  }

  String _productImageUrl(dynamic raw) {
    final value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final clean = value.startsWith('uploads/') ? value : 'uploads/$value';
    return ApiConfig.fileUrl(clean);
  }

  String get _pageTitle {
    switch ((widget.filter ?? '').toLowerCase()) {
      case 'today':
        return 'Today Orders';
      case 'today_revenue':
        return 'Today Revenue Orders';
      default:
        return 'All Orders';
    }
  }

  String get _emptyMessage {
    switch ((widget.filter ?? '').toLowerCase()) {
      case 'today':
        return 'There are no orders for today.';
      case 'today_revenue':
        return 'There are no paid orders for today.';
      default:
        return 'No orders found';
    }
  }

  Future<void> loadAll() async {
    setState(() => isLoading = true);

    try {
      final token = await _getToken();

      final statsRes = await http.get(
        ApiConfig.uri('/api/admin/orders/stats'),
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
          '/api/admin/orders',
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
        total = _asInt(stats['total']);
        pending = _asInt(stats['pending']);
        confirmed = _asInt(stats['confirmed']);
        packed = _asInt(stats['packed']);
        outForDelivery = _asInt(
          stats['out_for_delivery'] ?? stats['outForDelivery'],
        );
        delivered = _asInt(stats['delivered']);

        paid = _asInt(stats['paid']);
        payPending = _asInt(stats['pay_pending']);
        failed = _asInt(stats['failed']);

        orders = (list is List) ? list : [];
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

  List<dynamic> get filteredOrders {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return orders;

    return orders.where((o) {
      final orderId = (o['order_id'] ?? '').toString().toLowerCase();
      final sellerName = (o['seller_name'] ?? '').toString().toLowerCase();
      final userName = (o['user_name'] ?? '').toString().toLowerCase();
      final userId = (o['user_id'] ?? '').toString().toLowerCase();
      final orderStatus = (o['order_status'] ?? '').toString().toLowerCase();
      final paymentStatus =
      (o['payment_status'] ?? '').toString().toLowerCase();
      final totalAmount =
      (o['total_amount'] ?? o['amount'] ?? '').toString().toLowerCase();

      return orderId.contains(q) ||
          sellerName.contains(q) ||
          userName.contains(q) ||
          userId.contains(q) ||
          orderStatus.contains(q) ||
          paymentStatus.contains(q) ||
          totalAmount.contains(q);
    }).toList();
  }

  Color _orderStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.blue;
      case 'packed':
        return Colors.purple;
      case 'out for delivery':
      case 'outfordelivery':
      case 'out_for_delivery':
        return Colors.green;
      case 'delivered':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _paymentStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        softWrap: true,
        overflow: TextOverflow.visible,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  EdgeInsets _pagePadding(double width) {
    if (width >= 1200) {
      return const EdgeInsets.symmetric(horizontal: 24, vertical: 12);
    }
    if (width >= 800) {
      return const EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
  }

  double _contentMaxWidth(double width) {
    if (width >= 1500) return 1400;
    if (width >= 1200) return 1180;
    return width;
  }

  Widget _buildOverviewSection(List<PieSegment> segments, double width) {
    final padding = _pagePadding(width);

    Widget chips() {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: width - padding.horizontal),
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 10,
            runSpacing: 10,
            children: [
              Chip(label: Text('Total: $total')),
              Chip(label: Text('Pending: $pending')),
              Chip(label: Text('Confirmed: $confirmed')),
              Chip(label: Text('Packed: $packed')),
              Chip(label: Text('Out For Delivery: $outForDelivery')),
              Chip(label: Text('Delivered: $delivered')),
              Chip(label: Text('Paid: $paid')),
              Chip(label: Text('Pay Pending: $payPending')),
              Chip(label: Text('Failed: $failed')),
            ],
          ),
        ),
      );
    }

    return Card(
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
                  chips(),
                ],
              ),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: chips(),
              ),
            ),
          ],
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

  Future<void> showProductDetailsFromOrder(Map<String, dynamic> product) async {
    final productId = int.tryParse((product['product_id'] ?? '').toString()) ?? 0;

    if (productId > 0) {
      try {
        final token = await _getToken();
        final res = await http.get(
          ApiConfig.uri('/api/admin/products/$productId'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (res.statusCode == 200) {
          final data = Map<String, dynamic>.from(jsonDecode(res.body));
          if (!mounted) return;

          final imageUrl = _productImageUrl(
            data['prod_image_url'] ?? data['product_image_url'] ?? data['prod_image'] ?? data['product_image'],
          );

          showDialog(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: Container(
                width: 700,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              (data['prod_name'] ?? data['product_name'] ?? 'Product Details').toString(),
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                              title: (data['prod_name'] ?? data['product_name'] ?? 'Product Image').toString(),
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
                      Text('Brand: ${data['brand'] ?? '-'}'),
                      const SizedBox(height: 6),
                      Text('Category: ${data['category_name'] ?? '-'}'),
                      const SizedBox(height: 6),
                      Text('Seller: ${data['seller_name'] ?? '-'}'),
                      const SizedBox(height: 6),
                      Text('Price: ₹${data['prod_price'] ?? data['price'] ?? 0}'),
                      const SizedBox(height: 6),
                      Text('Stock: ${data['stock_quantity'] ?? data['stock'] ?? 0}'),
                      const SizedBox(height: 6),
                      Text('Unit: ${data['unit_type'] ?? '-'}'),
                      const SizedBox(height: 6),
                      Text('Status: ${data['prod_status'] ?? data['status'] ?? '-'}'),
                      const SizedBox(height: 6),
                      Text('Stock Status: ${data['stock_status'] ?? '-'}'),
                      const SizedBox(height: 6),
                      Text('Expiry: ${data['expiry_at'] ?? '-'}'),
                      const SizedBox(height: 12),
                      Text('Description: ${data['description'] ?? '-'}'),
                    ],
                  ),
                ),
              ),
            ),
          );
          return;
        }
      } catch (_) {}
    }

    if (!mounted) return;
    final imageUrl = _productImageUrl(product['product_image']);
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
                        (product['product_name'] ?? 'Product Details').toString(),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
                        title: (product['product_name'] ?? 'Product Image').toString(),
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
                Text('Quantity: ${product['ordered_qty'] ?? product['stock_quantity'] ?? '-'}'),
                const SizedBox(height: 6),
                Text('Price: ₹${product['ordered_price'] ?? product['price'] ?? 0}'),
                const SizedBox(height: 6),
                Text('Total: ₹${product['ordered_total'] ?? product['price'] ?? 0}'),
                const SizedBox(height: 6),
                Text('Brand: ${product['brand'] ?? '-'}'),
                const SizedBox(height: 6),
                Text('Unit: ${product['unit_type'] ?? '-'}'),
                const SizedBox(height: 6),
                Text('Description: ${product['description'] ?? '-'}'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> showOrderDetails(Map<String, dynamic> data) async {
    try {
      final token = await _getToken();
      final orderId = int.tryParse((data['order_id'] ?? '').toString()) ?? 0;
      if (orderId <= 0) return;

      final res = await http.get(
        ApiConfig.uri('/api/admin/orders/$orderId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) {
        throw Exception(res.body);
      }

      final fullData = Map<String, dynamic>.from(jsonDecode(res.body));
      final products = List<dynamic>.from(fullData['products'] ?? []);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            width: 780,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Order #${fullData['order_id'] ?? ''}',
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
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      Chip(label: Text('Order Status: ${fullData['order_status'] ?? '-'}')),
                      Chip(label: Text('Payment: ${fullData['payment_status'] ?? '-'}')),
                      Chip(label: Text('Method: ${fullData['payment_method'] ?? '-'}')),
                      Chip(label: Text('Amount: ₹${_formatAmount(fullData['total_amount'])}')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Seller: ${fullData['seller_name'] ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('User: ${fullData['user_name'] ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('Delivery Staff: ${fullData['delivery_staff_name'] ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('Date: ${fullData['order_date'] ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('Delivery Address: ${fullData['delivery_address'] ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('Pincode: ${fullData['pincode'] ?? '-'}'),
                  const SizedBox(height: 6),
                  Text('Notes: ${fullData['notes'] ?? '-'}'),
                  const SizedBox(height: 16),
                  const Text(
                    'Products',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  if (products.isEmpty)
                    const Text('No product details available')
                  else
                    ...products.map((p) {
                      final imageUrl = _productImageUrl(p['product_image']);
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => showProductDetailsFromOrder(Map<String, dynamic>.from(p)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(10),
                            leading: imageUrl.isNotEmpty
                                ? InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => _showImagePreview(
                                imageUrl,
                                title: (p['product_name'] ?? 'Product Image').toString(),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imageUrl,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const CircleAvatar(
                                    radius: 28,
                                    child: Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                            )
                                : const CircleAvatar(
                              radius: 28,
                              child: Icon(Icons.image_not_supported),
                            ),
                            title: Text((p['product_name'] ?? 'Unnamed Product').toString()),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Qty: ${p['ordered_qty'] ?? p['stock_quantity'] ?? '-'}'),
                                Text('Price: ₹${p['ordered_price'] ?? p['price'] ?? 0}'),
                                Text('Total: ₹${p['ordered_total'] ?? p['price'] ?? 0}'),
                                if ((p['brand'] ?? '').toString().isNotEmpty)
                                  Text('Brand: ${p['brand']}'),
                                if ((p['unit_type'] ?? '').toString().isNotEmpty)
                                  Text('Unit: ${p['unit_type']}'),
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                          ),
                        ),
                      );
                    }).toList(),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Details error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = [
      PieSegment(label: 'Pending', value: pending),
      PieSegment(label: 'Confirmed', value: confirmed),
      PieSegment(label: 'Packed', value: packed),
      PieSegment(label: 'Out For Delivery', value: outForDelivery),
      PieSegment(label: 'Delivered', value: delivered),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final padding = _pagePadding(width);
            final compact = width < 700;
            final maxWidth = _contentMaxWidth(width);

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: padding,
                  child: Column(
                    children: [
                      _buildOverviewSection(segments, width),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          labelText:
                          'Search order (id/seller/user/status/payment/amount)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => query = v),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filteredOrders.isEmpty
                            ? Center(child: Text(_emptyMessage))
                            : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: filteredOrders.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final o = filteredOrders[index];

                            final orderId = int.tryParse(
                              (o['order_id'] ?? '').toString(),
                            ) ??
                                0;
                            final sellerName =
                            (o['seller_name'] ?? '—').toString();
                            final userName =
                            (o['user_name'] ?? '—').toString();
                            final userId =
                            (o['user_id'] ?? '—').toString();
                            final orderStatus =
                            (o['order_status'] ?? 'Pending').toString();
                            final paymentStatus =
                            (o['payment_status'] ?? 'Pending').toString();
                            final totalAmount =
                            (o['total_amount'] ?? o['amount'] ?? 0);
                            final orderDate =
                            (o['order_date'] ?? '').toString();

                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => showOrderDetails(
                                Map<String, dynamic>.from(o),
                              ),
                              child: AdminItemCard(
                                leading: CircleAvatar(
                                  radius: compact ? 22 : 28,
                                  child: FittedBox(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(
                                        orderId == 0 ? '?' : '$orderId',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                title: 'Order #$orderId',
                                lines: [
                                  'Seller: $sellerName',
                                  'User: $userName (ID: $userId)',
                                  'Amount: ₹${_formatAmount(totalAmount)}',
                                  if (orderDate.isNotEmpty) 'Date: $orderDate',
                                ],
                                trailing: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: compact ? width * 0.72 : width * 0.42,
                                  ),
                                  child: Align(
                                    alignment: compact
                                        ? Alignment.centerLeft
                                        : Alignment.centerRight,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: compact
                                          ? WrapAlignment.start
                                          : WrapAlignment.end,
                                      children: [
                                        _statusPill(
                                          'Order: $orderStatus',
                                          _orderStatusColor(orderStatus),
                                        ),
                                        _statusPill(
                                          'Payment: $paymentStatus',
                                          _paymentStatusColor(paymentStatus),
                                        ),
                                      ],
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
          },
        ),
      ),
    );
  }
}