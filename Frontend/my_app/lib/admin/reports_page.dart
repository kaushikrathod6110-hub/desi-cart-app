import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:my_app/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:universal_html/html.dart' as html;

import '../screens/token_storage.dart';
import 'all_delivery_staff_page.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool loading = true;
  bool detailLoading = false;

  String range = "today";
  DateTime? customStartDate;
  DateTime? customEndDate;

  Map<String, dynamic> cards = {};
  Map<String, dynamic> orderStatusCounts = {};
  Map<String, dynamic> paymentStatusCounts = {};
  List<dynamic> revenueByDay = [];

  List<dynamic> users = [];
  List<dynamic> sellers = [];
  List<dynamic> products = [];
  List<dynamic> orders = [];
  double ordersGrandTotal = 0;

  String currentView = "overview"; // overview / users / sellers / products / orders / detail
  String selectedType = ""; // user / seller / order
  Map<String, dynamic>? selectedDetail;

  String userSearch = "";
  String sellerSearch = "";
  String productSearch = "";
  String orderSearch = "";
  String orderPaymentStatusFilter = "All";
  String orderStatusFilter = "All";
  String selectedRevenueDay = "";

  final TextEditingController userSearchController = TextEditingController();
  final TextEditingController sellerSearchController = TextEditingController();
  final TextEditingController productSearchController = TextEditingController();
  final TextEditingController orderSearchController = TextEditingController();

  Timer? _productsAutoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _startProductsAutoRefresh();
    loadAllReports();
  }

  @override
  void dispose() {
    _productsAutoRefreshTimer?.cancel();
    userSearchController.dispose();
    sellerSearchController.dispose();
    productSearchController.dispose();
    orderSearchController.dispose();
    super.dispose();
  }

  void _startProductsAutoRefresh() {
    _productsAutoRefreshTimer?.cancel();
    _productsAutoRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!mounted || loading || detailLoading || currentView != "products") return;
      try {
        await loadProducts();
      } catch (_) {}
    });
  }

  int _productStock(dynamic p) {
    return ((p["stock"] ?? p["stock_quantity"] ?? 0) as num?)?.toInt() ??
        int.tryParse((p["stock"] ?? p["stock_quantity"] ?? 0).toString()) ??
        0;
  }

  double _filteredProductsInventoryValue() {
    double total = 0;
    for (final p in _filteredProducts()) {
      total += _d(p["price"]) * _productStock(p);
    }
    return total;
  }

  int _filteredProductsTotalStock() {
    int total = 0;
    for (final p in _filteredProducts()) {
      total += _productStock(p);
    }
    return total;
  }

  int _filteredProductsInStockCount() {
    return _filteredProducts().where((p) => _productStock(p) > 0).length;
  }

  double _filteredProductsAverageRating() {
    final rated = _filteredProducts().where((p) => ((p["review_count"] ?? 0) as num?)?.toInt() != 0).toList();
    if (rated.isEmpty) return 0;
    double total = 0;
    for (final p in rated) {
      total += _d(p["avg_rating"]);
    }
    return total / rated.length;
  }

  int _filteredProductsRatedCount() {
    return _filteredProducts().where((p) => ((p["review_count"] ?? 0) as num?)?.toInt() != 0).length;
  }

  int _filteredProductsTotalReviews() {
    int total = 0;
    for (final p in _filteredProducts()) {
      total += ((p["review_count"] ?? 0) as num?)?.toInt() ?? 0;
    }
    return total;
  }

  List<dynamic> _topProductsByStock([int limit = 5]) {
    final items = List<dynamic>.from(_filteredProducts());
    items.sort((a, b) => _productStock(b).compareTo(_productStock(a)));
    return items.take(limit).toList();
  }

  Future<void> _refreshProductsOnly() async {
    await loadProducts();
    if (mounted) setState(() {});
  }

  Future<String> _getToken() async {
    final storage = TokenStorage();
    final token = await storage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw Exception("Token missing. Please login again.");
    }
    return token;
  }

  String _formatApiDate(DateTime date) {
    return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Uri _buildReportsUri(String path, {bool includeRange = true}) {
    final params = <String, String>{};

    if (includeRange) {
      if (range == "custom" && customStartDate != null && customEndDate != null) {
        params["start_date"] = _formatApiDate(customStartDate!);
        params["end_date"] = _formatApiDate(customEndDate!);
      } else {
        params["range"] = range;
      }
    }

    return ApiConfig.uri(path, queryParameters: params.isEmpty ? null : params);
  }

  Future<void> _applyRange(String value, {DateTime? start, DateTime? end}) async {
    setState(() {
      range = value;
      customStartDate = start;
      customEndDate = end;
      selectedDetail = null;
      selectedType = "";
      currentView = "overview";
    });
    await loadAllReports();
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final initialStart = customStartDate ?? now.subtract(const Duration(days: 6));
    final initialEnd = customEndDate ?? now;

    final start = await showDatePicker(
      context: context,
      initialDate: initialStart,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: "Select From Date",
    );

    if (start == null || !mounted) return;

    final end = await showDatePicker(
      context: context,
      initialDate: initialEnd.isBefore(start) ? start : initialEnd,
      firstDate: start,
      lastDate: now,
      helpText: "Select To Date",
    );

    if (end == null || !mounted) return;

    await _applyRange("custom", start: start, end: end);
  }

  Future<void> loadAllReports() async {
    setState(() => loading = true);
    try {
      await Future.wait([
        loadSummary(),
        loadUsers(),
        loadSellers(),
        loadProducts(),
        loadOrders(),
      ]);
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

  Future<void> loadSummary() async {
    final token = await _getToken();

    final res = await http.get(
      _buildReportsUri("/api/admin/reports/summary"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("Summary API failed: ${res.statusCode} ${res.body}");
    }

    final data = jsonDecode(res.body);
    cards = Map<String, dynamic>.from(data["cards"] ?? {});
    orderStatusCounts =
    Map<String, dynamic>.from(data["order_status_counts"] ?? {});
    paymentStatusCounts =
    Map<String, dynamic>.from(data["payment_status_counts"] ?? {});
    revenueByDay = List<dynamic>.from(data["revenue_by_day"] ?? []);
  }

  Future<void> loadUsers() async {
    final token = await _getToken();

    final res = await http.get(
      _buildReportsUri("/api/admin/reports/users"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("Users API failed: ${res.statusCode} ${res.body}");
    }

    final data = jsonDecode(res.body);
    users = List<dynamic>.from(data["users"] ?? []);
  }

  Future<void> loadSellers() async {
    final token = await _getToken();

    final res = await http.get(
      _buildReportsUri("/api/admin/reports/sellers"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("Sellers API failed: ${res.statusCode} ${res.body}");
    }

    final data = jsonDecode(res.body);
    sellers = List<dynamic>.from(data["sellers"] ?? []);
  }

  Future<void> loadProducts() async {
    final token = await _getToken();

    final res = await http.get(
      _buildReportsUri("/api/admin/reports/products"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("Products API failed: ${res.statusCode} ${res.body}");
    }

    final data = jsonDecode(res.body);
    products = List<dynamic>.from(data["products"] ?? []);
  }

  Future<void> loadOrders() async {
    final token = await _getToken();

    final res = await http.get(
      _buildReportsUri("/api/admin/reports/orders"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("Orders API failed: ${res.statusCode} ${res.body}");
    }

    final data = jsonDecode(res.body);
    orders = List<dynamic>.from(data["orders"] ?? []);
    ordersGrandTotal = _d(data["grand_total"]);
  }

  Future<void> openUserReport(int userId) async {
    setState(() {
      detailLoading = true;
      selectedType = "user";
      selectedDetail = null;
      currentView = "detail";
    });

    try {
      final token = await _getToken();
      final res = await http.get(
        _buildReportsUri("/api/admin/reports/user/$userId"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) {
        throw Exception("User report failed: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body);

      if (mounted) {
        setState(() {
          selectedDetail = Map<String, dynamic>.from(data);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          currentView = "users";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => detailLoading = false);
      }
    }
  }

  Future<void> openSellerReport(int sellerId) async {
    setState(() {
      detailLoading = true;
      selectedType = "seller";
      selectedDetail = null;
      currentView = "detail";
    });

    try {
      final token = await _getToken();
      final res = await http.get(
        _buildReportsUri("/api/admin/reports/seller/$sellerId"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) {
        throw Exception("Seller report failed: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body);

      if (mounted) {
        setState(() {
          selectedDetail = Map<String, dynamic>.from(data);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          currentView = "sellers";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => detailLoading = false);
      }
    }
  }

  Future<void> openOrderReport(int orderId) async {
    setState(() {
      detailLoading = true;
      selectedType = "order";
      selectedDetail = null;
      currentView = "detail";
    });

    try {
      final token = await _getToken();
      final res = await http.get(
        _buildReportsUri("/api/admin/reports/order/$orderId"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) {
        throw Exception("Order report failed: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body);

      if (mounted) {
        setState(() {
          selectedDetail = Map<String, dynamic>.from(data);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          currentView = "orders";
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => detailLoading = false);
      }
    }
  }




  Future<Map<String, dynamic>> _fetchUserReportData(int userId) async {
    final token = await _getToken();
    final res = await http.get(
      _buildReportsUri("/api/admin/reports/user/$userId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("User report failed: ${res.statusCode} ${res.body}");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Future<Map<String, dynamic>> _fetchSellerReportData(int sellerId) async {
    final token = await _getToken();
    final res = await http.get(
      _buildReportsUri("/api/admin/reports/seller/$sellerId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode != 200) {
      throw Exception("Seller report failed: ${res.statusCode} ${res.body}");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  Future<void> showUserReportDialog(int userId) async {
    try {
      final data = await _fetchUserReportData(userId);
      if (!mounted) return;

      final profile = Map<String, dynamic>.from(data["profile"] ?? {});
      final stats = Map<String, dynamic>.from(data["stats"] ?? {});
      final recentOrders = List<dynamic>.from(data["recent_orders"] ?? []);

      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text("User Details #$userId"),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (profile["name"] ?? "-").toString(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _miniChip("User ID: ${profile["id"] ?? "-"}"),
                              _miniChip("Email: ${profile["email"] ?? "-"}"),
                              _miniChip("Mobile: ${profile["mobile"] ?? "-"}"),
                              _miniChip("Registered: ${_date(profile["registration_at"])}"),
                              _miniChip("Orders: ${stats["total_orders"] ?? 0}"),
                              _miniChip("Paid Orders: ${stats["paid_orders"] ?? 0}"),
                              _miniChip("Pending: ${stats["pending_payments"] ?? 0}"),
                              _miniChip("Failed: ${stats["failed_payments"] ?? 0}"),
                              _miniChip("Total Spent: Rs. ${_money(stats["total_spent"])}"),
                              _miniChip("Avg Order: Rs. ${_money(stats["avg_order_value"])}"),
                              _miniChip("Preferred Payment: ${stats["preferred_payment_method"] ?? "N/A"}"),
                              _miniChip("Last Order: ${_date(stats["last_order_date"])}"),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Recent Orders",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (recentOrders.isEmpty)
                      const Text("No recent orders found.")
                    else
                      Column(
                        children: recentOrders.map((o) {
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _miniChip("Order ID: ${o["order_id"] ?? "-"}"),
                                _miniChip("Date: ${_date(o["order_date"])}"),
                                _miniChip("Amount: Rs. ${_money(o["total_amount"])}"),
                                _miniChip("Order Status: ${o["order_status"] ?? "-"}"),
                                _miniChip("Payment: ${o["payment_status"] ?? "-"}"),
                                _miniChip("Method: ${o["payment_method"] ?? "-"}"),
                                if (o["seller_id"] != null)
                                  _clickableMiniChip(
                                    "Seller ID: ${o["seller_id"]}",
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      showSellerReportDialog(int.parse(o["seller_id"].toString()));
                                    },
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Close"),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Future<void> showSellerReportDialog(int sellerId) async {
    try {
      final data = await _fetchSellerReportData(sellerId);
      if (!mounted) return;

      final profile = Map<String, dynamic>.from(data["profile"] ?? {});
      final stats = Map<String, dynamic>.from(data["stats"] ?? {});
      final recentOrders = List<dynamic>.from(data["recent_orders"] ?? []);

      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text("Seller Details #$sellerId"),
            content: SizedBox(
              width: 760,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (profile["name"] ?? "-").toString(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _miniChip("Seller ID: ${profile["id"] ?? "-"}"),
                              _miniChip("Email: ${profile["email"] ?? "-"}"),
                              _miniChip("Mobile: ${profile["mobile"] ?? "-"}"),
                              _miniChip("Registered: ${_date(profile["registration_at"])}"),
                              _miniChip("Products: ${stats["total_products"] ?? 0}"),
                              _miniChip("Orders: ${stats["total_orders"] ?? 0}"),
                              _miniChip("Paid Orders: ${stats["paid_orders"] ?? 0}"),
                              _miniChip("Pending: ${stats["pending_payments"] ?? 0}"),
                              _miniChip("Failed: ${stats["failed_payments"] ?? 0}"),
                              _miniChip("Revenue: Rs. ${_money(stats["total_revenue"])}"),
                              _miniChip("Avg Order: Rs. ${_money(stats["avg_order_value"])}"),
                              _miniChip("Preferred Payment: ${stats["preferred_payment_method"] ?? "N/A"}"),
                              _miniChip("Last Order: ${_date(stats["last_order_date"])}"),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      "Recent Orders",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (recentOrders.isEmpty)
                      const Text("No recent orders found.")
                    else
                      Column(
                        children: recentOrders.map((o) {
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _miniChip("Order ID: ${o["order_id"] ?? "-"}"),
                                _miniChip("Date: ${_date(o["order_date"])}"),
                                _miniChip("Amount: Rs. ${_money(o["total_amount"])}"),
                                _miniChip("Order Status: ${o["order_status"] ?? "-"}"),
                                _miniChip("Payment: ${o["payment_status"] ?? "-"}"),
                                _miniChip("Method: ${o["payment_method"] ?? "-"}"),
                                if (o["user_id"] != null)
                                  _clickableMiniChip(
                                    "User ID: ${o["user_id"]}",
                                    onTap: () {
                                      Navigator.of(context).pop();
                                      showUserReportDialog(int.parse(o["user_id"].toString()));
                                    },
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Close"),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Future<void> openOrderProducts(int orderId) async {
    try {
      final token = await _getToken();
      final res = await http.get(
        _buildReportsUri("/api/admin/reports/order/$orderId/products"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) {
        throw Exception("Product details failed: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body);
      final products = List<dynamic>.from(data["products"] ?? []);

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text("Products of Order #$orderId"),
            content: SizedBox(
              width: 700,
              child: products.isEmpty
                  ? const Text("No product details found for this order.")
                  : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: products.map((p) {
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _productName(p),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _miniChip("Product ID: ${p["product_id"] ?? "-"}"),
                              if (p["ordered_qty"] != null)
                                _miniChip("Qty: ${p["ordered_qty"]}"),
                              if (p["ordered_price"] != null)
                                _miniChip("Total Price: Rs. ${_money(p["ordered_price"])}"),
                              if (p["ordered_total"] != null)
                                _miniChip("Item Total: Rs. ${_money(p["ordered_total"])}"),
                              _miniChip("Price: Rs. ${_money(p["price"])}"),
                              _miniChip("Stock: ${p["stock"] ?? "-"}"),
                              _miniChip("Brand: ${p["brand"] ?? "-"}"),
                              _miniChip("Category ID: ${p["category_id"] ?? "-"}"),
                              _clickableMiniChip(
                                "Seller ID: ${p["seller_id"] ?? "-"}",
                                onTap: p["seller_id"] != null
                                    ? () {
                                  Navigator.of(context).pop();
                                  showSellerReportDialog(int.parse(p["seller_id"].toString()));
                                }
                                    : null,
                              ),
                              _miniChip("Status: ${p["status"] ?? "-"}"),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Description: ${(p["description"] ?? "-").toString().trim().isEmpty ? "-" : p["description"]}",
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Future<void> _changeRange(String v) async {
    if (v == "custom") {
      await _selectCustomDateRange();
      return;
    }
    await _applyRange(v);
  }

  Future<void> downloadOrdersPdf() async {
    final filteredOrders = _filteredOrders();
    if (filteredOrders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No orders data to export")),
        );
      }
      return;
    }

    final pdf = pw.Document();

    double totalAmount = 0;
    final rows = <List<String>>[];
    for (final o in filteredOrders) {
      final amount = _d(o["amount"]);
      totalAmount += amount;
      rows.add([
        "${o["order_id"] ?? "-"}",
        _productName(o),
        "${o["user_id"] ?? "-"}",
        "${o["seller_id"] ?? "-"}",
        "${o["payment_status"] ?? "-"}",
        "Rs. ${_money(amount)}",
      ]);
    }

    rows.add(["", "", "", "", "Total Amount", "Rs. ${_money(totalAmount)}"]);

    final filename = "orders_report_${range == "custom" ? "custom_range" : range}.pdf";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text(
            "Orders Report",
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text("Date Range: ${_rangeLabel(range)}"),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.0),
              1: const pw.FlexColumnWidth(2.8),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.4),
              5: const pw.FlexColumnWidth(1.2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell("Order ID", bold: true),
                  _pdfCell("Product Name", bold: true),
                  _pdfCell("User ID", bold: true),
                  _pdfCell("Seller ID", bold: true),
                  _pdfCell("Payment Status", bold: true),
                  _pdfCell("Amount", bold: true),
                ],
              ),
              ...rows.map(
                    (r) => pw.TableRow(
                  children: [
                    _pdfCell(r[0]),
                    _pdfCell(r[1]),
                    _pdfCell(r[2]),
                    _pdfCell(r[3]),
                    _pdfCell(r[4], bold: r[4] == "Total Amount"),
                    _pdfCell(r[5], bold: r[4] == "Total Amount"),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$filename downloaded")),
      );
    }
  }

  Future<void> downloadCurrentPdf() async {
    if (selectedDetail == null) return;

    final pdf = pw.Document();
    final isUser = selectedType == "user";
    final isSeller = selectedType == "seller";
    final isOrder = selectedType == "order";

    if (isOrder) {
      final profile = Map<String, dynamic>.from(selectedDetail!["profile"] ?? {});
      final stats = Map<String, dynamic>.from(selectedDetail!["stats"] ?? {});
      final orderProducts = List<dynamic>.from(selectedDetail!["products"] ?? []);
      final filename = "order_report_${profile["order_id"] ?? "data"}.pdf";

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Text(
              "Order Report",
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                _pdfRow("Order ID", "${profile["order_id"] ?? ""}"),
                _pdfRow("Order Date", _date(profile["order_date"])),
                _pdfRow("Amount", "Rs. ${_money(stats["total_amount"])}"),
                _pdfRow("Order Status", "${stats["order_status"] ?? ""}"),
                _pdfRow("Payment Status", "${stats["payment_status"] ?? ""}"),
                _pdfRow("Payment Method", "${stats["payment_method"] ?? ""}"),
                _pdfRow("User ID", "${profile["user_id"] ?? ""}"),
                _pdfRow("User Name", "${profile["user_name"] ?? ""}"),
                _pdfRow("User Email", "${profile["user_email"] ?? ""}"),
                _pdfRow("User Mobile", "${profile["user_mobile"] ?? ""}"),
                _pdfRow("Seller ID", "${profile["seller_id"] ?? ""}"),
                _pdfRow("Seller Name", "${profile["seller_name"] ?? ""}"),
                _pdfRow("Seller Email", "${profile["seller_email"] ?? ""}"),
                _pdfRow("Seller Mobile", "${profile["seller_mobile"] ?? ""}"),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              "Products",
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (orderProducts.isEmpty)
              pw.Text("No product details found.")
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2.8),
                  1: const pw.FlexColumnWidth(0.9),
                  2: const pw.FlexColumnWidth(1.3),
                  3: const pw.FlexColumnWidth(1.4),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _pdfCell("Product Name", bold: true),
                      _pdfCell("Qty", bold: true),
                      _pdfCell("Total Price", bold: true),
                      _pdfCell("Item Total", bold: true),
                    ],
                  ),
                  ...orderProducts.map((p) => pw.TableRow(children: [
                    _pdfCell(_productName(p)),
                    _pdfCell("${p["ordered_qty"] ?? "-"}"),
                    _pdfCell(
                      p["ordered_price"] != null
                          ? "Rs. ${_money(p["ordered_price"])}"
                          : "-",
                    ),
                    _pdfCell(
                      p["ordered_total"] != null
                          ? "Rs. ${_money(p["ordered_total"])}"
                          : "-",
                    ),
                  ])),
                ],
              ),
          ],
        ),
      );

      final Uint8List bytes = await pdf.save();
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute("download", filename)
        ..click();
      html.Url.revokeObjectUrl(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("$filename downloaded")),
        );
      }
      return;
    }

    final profile = Map<String, dynamic>.from(selectedDetail!["profile"] ?? {});
    final stats = Map<String, dynamic>.from(selectedDetail!["stats"] ?? {});
    final recentOrders =
    List<dynamic>.from(selectedDetail!["recent_orders"] ?? []);
    final paymentMethodCounts = Map<String, dynamic>.from(
      selectedDetail!["payment_method_counts"] ?? {},
    );
    final orderCounts = Map<String, dynamic>.from(
      selectedDetail!["order_status_counts"] ?? {},
    );
    final paymentCounts = Map<String, dynamic>.from(
      selectedDetail!["payment_status_counts"] ?? {},
    );

    final String title = isUser ? "User Report" : "Seller Report";
    final String filename =
        "${selectedType}_report_${profile["id"] ?? "data"}.pdf";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text("Date Range: ${_rangeLabel(range)}"),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("Name: ${profile["name"] ?? "-"}"),
                pw.Text("Email: ${profile["email"] ?? "-"}"),
                pw.Text("Mobile: ${profile["mobile"] ?? "-"}"),
                pw.Text("Joined: ${_date(profile["registration_at"])}"),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            "Summary",
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: [
              if (isUser) ...[
                _pdfRow("Total Orders", "${stats["total_orders"] ?? 0}"),
                _pdfRow("Total Spent", "Rs. ${_money(stats["total_spent"])}"),
              ] else ...[
                _pdfRow("Total Products", "${stats["total_products"] ?? 0}"),
                _pdfRow("Total Orders", "${stats["total_orders"] ?? 0}"),
                _pdfRow(
                  "Total Revenue",
                  "Rs. ${_money(stats["total_revenue"])}",
                ),
              ],
              _pdfRow(
                "Average Order Value",
                "Rs. ${_money(stats["avg_order_value"])}",
              ),
              _pdfRow("Paid Orders", "${stats["paid_orders"] ?? 0}"),
              _pdfRow("Pending Payments", "${stats["pending_payments"] ?? 0}"),
              _pdfRow("Failed Payments", "${stats["failed_payments"] ?? 0}"),
              _pdfRow(
                "Preferred Payment Method",
                "${stats["preferred_payment_method"] ?? "N/A"}",
              ),
              _pdfRow("Last Order Date", _date(stats["last_order_date"])),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            "Order Status Counts",
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          _pdfMapTable(orderCounts),
          pw.SizedBox(height: 16),
          pw.Text(
            "Payment Status Counts",
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          _pdfMapTable(paymentCounts),
          pw.SizedBox(height: 16),
          pw.Text(
            "Payment Method Usage",
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          _pdfMapTable(paymentMethodCounts),
          pw.SizedBox(height: 16),
          pw.Text(
            "Recent Orders",
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          if (recentOrders.isEmpty)
            pw.Text("No recent orders found.")
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell("Order ID", bold: true),
                    _pdfCell("Date", bold: true),
                    _pdfCell("Amount", bold: true),
                    _pdfCell("Order Status", bold: true),
                    _pdfCell("Payment", bold: true),
                    _pdfCell("Method", bold: true),
                  ],
                ),
                ...recentOrders.map((o) {
                  return pw.TableRow(
                    children: [
                      _pdfCell("${o["order_id"] ?? ""}"),
                      _pdfCell(_date(o["order_date"])),
                      _pdfCell("Rs. ${_money(o["total_amount"])}"),
                      _pdfCell("${o["order_status"] ?? ""}"),
                      _pdfCell("${o["payment_status"] ?? ""}"),
                      _pdfCell("${o["payment_method"] ?? ""}"),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();

    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$filename downloaded")),
      );
    }
  }

  pw.TableRow _pdfRow(String key, String value) {
    return pw.TableRow(
      children: [
        _pdfCell(key, bold: true),
        _pdfCell(value),
      ],
    );
  }

  pw.Widget _pdfMapTable(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return pw.Text("No data");
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _pdfCell("Label", bold: true),
            _pdfCell("Count", bold: true),
          ],
        ),
        ...data.entries.map((e) {
          return pw.TableRow(
            children: [
              _pdfCell(e.key),
              _pdfCell("${e.value ?? 0}"),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: 10,
        ),
      ),
    );
  }

  double _d(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return double.tryParse(v.toString()) ?? 0;
  }

  double _maxY(List<double> values) {
    if (values.isEmpty) return 1;
    final mx = values.reduce((a, b) => a > b ? a : b);
    if (mx <= 3) return 4;
    return mx + 2;
  }

  String _rangeLabel(String r) {
    switch (r) {
      case "today":
        return "Today";
      case "yesterday":
        return "Yesterday";
      case "month":
        return "This Month";
      case "custom":
        if (customStartDate != null && customEndDate != null) {
          return "${_date(customStartDate)} to ${_date(customEndDate)}";
        }
        return "Custom Range";
      case "week":
      default:
        return "Last 7 Days";
    }
  }

  IconData _rangeIcon(String r) {
    switch (r) {
      case "today":
        return Icons.today;
      case "yesterday":
        return Icons.history_toggle_off;
      case "month":
        return Icons.calendar_month;
      case "custom":
        return Icons.edit_calendar;
      case "week":
      default:
        return Icons.date_range;
    }
  }

  String _money(dynamic v) {
    final n = _d(v);
    return n.toStringAsFixed(2);
  }

  String _productName(dynamic item) {
    if (item is! Map) return 'No Product';

    final keys = [
      'product_name',
      'prod_name',
      'name',
      'product_title',
      'title',
      'order_item_name',
    ];

    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    final names = item['product_names'];
    if (names is List && names.isNotEmpty) {
      final joined = names
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .join(', ');
      if (joined.isNotEmpty) return joined;
    }

    return 'No Product';
  }


  String _orderProductLabel(dynamic item) {
    if (item is! Map) return 'No Product';

    final keys = [
      'prod_name',
      'product_name',
      'name',
      'product_title',
      'title',
      'order_item_name',
    ];

    for (final key in keys) {
      final value = item[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }

    final names = item['product_names'];
    if (names is List && names.isNotEmpty) {
      final joined = names
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .join(', ');
      if (joined.isNotEmpty) return joined;
    }

    return 'No Product';
  }

  String _date(dynamic v) {
    if (v == null || v.toString().isEmpty) return "-";
    try {
      final d = DateTime.parse(v.toString()).toLocal();
      return "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";
    } catch (_) {
      return v.toString();
    }
  }

  List<dynamic> _filteredUsers() {
    if (userSearch.trim().isEmpty) return users;

    final q = userSearch.toLowerCase().trim();

    return users.where((u) {
      final name = (u["user_name"] ?? "").toString().toLowerCase();
      final email = (u["user_email"] ?? "").toString().toLowerCase();
      final mobile = (u["user_mobile"] ?? "").toString().toLowerCase();
      final id = (u["user_id"] ?? "").toString().toLowerCase();

      return name.contains(q) ||
          email.contains(q) ||
          mobile.contains(q) ||
          id.contains(q);
    }).toList();
  }

  List<dynamic> _filteredSellers() {
    if (sellerSearch.trim().isEmpty) return sellers;

    final q = sellerSearch.toLowerCase().trim();

    return sellers.where((s) {
      final name = (s["seller_name"] ?? "").toString().toLowerCase();
      final email = (s["seller_email"] ?? "").toString().toLowerCase();
      final mobile = (s["seller_mobile"] ?? "").toString().toLowerCase();
      final id = (s["seller_id"] ?? "").toString().toLowerCase();

      return name.contains(q) ||
          email.contains(q) ||
          mobile.contains(q) ||
          id.contains(q);
    }).toList();
  }

  List<dynamic> _filteredProducts() {
    if (productSearch.trim().isEmpty) return products;

    final q = productSearch.toLowerCase().trim();

    return products.where((p) {
      final id = (p["product_id"] ?? "").toString().toLowerCase();
      final name = (p["product_name"] ?? "").toString().toLowerCase();
      final sellerId = (p["seller_id"] ?? "").toString().toLowerCase();
      final status = (p["status"] ?? "").toString().toLowerCase();
      final price = (p["price"] ?? "").toString().toLowerCase();
      final stock = (p["stock"] ?? p["stock_quantity"] ?? "").toString().toLowerCase();
      final rating = (p["avg_rating"] ?? "").toString().toLowerCase();
      final reviews = (p["review_count"] ?? "").toString().toLowerCase();

      return id.contains(q) ||
          name.contains(q) ||
          sellerId.contains(q) ||
          status.contains(q) ||
          price.contains(q) ||
          stock.contains(q) ||
          rating.contains(q) ||
          reviews.contains(q);
    }).toList();
  }

  List<dynamic> _filteredOrders() {
    final q = orderSearch.toLowerCase().trim();

    return orders.where((o) {
      final orderId = (o["order_id"] ?? "").toString().toLowerCase();
      final prodName = _productName(o).toLowerCase();
      final userId = (o["user_id"] ?? "").toString().toLowerCase();
      final sellerId = (o["seller_id"] ?? "").toString().toLowerCase();
      final amount = (o["amount"] ?? o["total_amount"] ?? "").toString().toLowerCase();
      final paymentStatus = (o["payment_status"] ?? "").toString();
      final orderStatus = (o["order_status"] ?? "").toString();
      final orderDay = (o["order_day"] ?? o["order_date"] ?? "").toString().split('T').first;

      final matchesSearch = q.isEmpty ||
          orderId.contains(q) ||
          prodName.contains(q) ||
          userId.contains(q) ||
          sellerId.contains(q) ||
          amount.contains(q) ||
          paymentStatus.toLowerCase().contains(q) ||
          orderStatus.toLowerCase().contains(q);

      final matchesPayment = orderPaymentStatusFilter == "All" ||
          paymentStatus.toLowerCase() == orderPaymentStatusFilter.toLowerCase();
      final matchesOrderStatus = orderStatusFilter == "All" ||
          orderStatus.toLowerCase() == orderStatusFilter.toLowerCase();
      final matchesRevenueDay = selectedRevenueDay.isEmpty || orderDay == selectedRevenueDay;
      final matchesRevenuePayment = selectedRevenueDay.isEmpty || paymentStatus.toLowerCase() == "paid";

      return matchesSearch && matchesPayment && matchesOrderStatus && matchesRevenueDay && matchesRevenuePayment;
    }).toList();
  }

  Future<void> _openOrdersView({String? orderStatus, String? paymentStatus, String? revenueDay, bool resetFilters = false}) async {
    setState(() {
      currentView = "orders";
      if (resetFilters) {
        orderSearchController.clear();
        orderSearch = "";
        orderPaymentStatusFilter = "All";
        orderStatusFilter = "All";
        selectedRevenueDay = "";
      }
      if (orderStatus != null) {
        orderStatusFilter = orderStatus;
      }
      if (paymentStatus != null) {
        orderPaymentStatusFilter = paymentStatus;
      }
      if (revenueDay != null) {
        selectedRevenueDay = revenueDay;
      }
    });
    await loadOrders();
  }

  List<int> _extractOrderIds(dynamic item) {
    final ids = <int>[];
    if (item is! Map) return ids;
    final raw = item["order_ids"];
    if (raw is List) {
      for (final v in raw) {
        final parsed = int.tryParse(v.toString());
        if (parsed != null && !ids.contains(parsed)) {
          ids.add(parsed);
        }
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      for (final part in raw.split(',')) {
        final parsed = int.tryParse(part.trim());
        if (parsed != null && !ids.contains(parsed)) {
          ids.add(parsed);
        }
      }
    }
    final single = int.tryParse((item["order_id"] ?? '').toString());
    if (single != null && !ids.contains(single)) {
      ids.insert(0, single);
    }
    return ids;
  }

  Future<void> _openProductsForOrderRow(dynamic item) async {
    final ids = _extractOrderIds(item);
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      await openOrderProducts(ids.first);
      return;
    }

    try {
      final token = await _getToken();
      final rangeUri = _buildReportsUri('/api/admin/reports/order/${ids.first}/products');
      final params = Map<String, String>.from(rangeUri.queryParameters);
      params['order_ids'] = ids.join(',');
      final res = await http.get(
        ApiConfig.uri('/api/admin/reports/order/${ids.first}/products', queryParameters: params),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode != 200) {
        throw Exception("Product details failed: ${res.statusCode} ${res.body}");
      }

      final data = jsonDecode(res.body);
      final products = List<dynamic>.from(data["products"] ?? []);
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: Text("Products of Orders #${ids.join(', ')}"),
            content: SizedBox(
              width: 760,
              child: products.isEmpty
                  ? const Text("No product details found for these orders.")
                  : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: products.map((p) {
                    final linkedIds = (p["order_ids"] is List)
                        ? (p["order_ids"] as List).map((e) => e.toString()).join(', ')
                        : ids.join(', ');
                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _productName(p),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 8,
                            children: [
                              _miniChip("Order ID(s): $linkedIds"),
                              _miniChip("Product ID: ${p["product_id"] ?? "-"}"),
                              if (p["ordered_qty"] != null) _miniChip("Qty: ${p["ordered_qty"]}"),
                              if (p["ordered_price"] != null) _miniChip("Total Price: Rs. ${_money(p["ordered_price"])}"),
                              if (p["ordered_total"] != null) _miniChip("Item Total: Rs. ${_money(p["ordered_total"])}"),
                              _miniChip("Price: Rs. ${_money(p["price"])}"),
                              _miniChip("Stock: ${p["stock"] ?? "-"}"),
                              _miniChip("Brand: ${p["brand"] ?? "-"}"),
                              _miniChip("Category ID: ${p["category_id"] ?? "-"}"),
                              _clickableMiniChip(
                                "Seller ID: ${p["seller_id"] ?? "-"}",
                                onTap: p["seller_id"] != null
                                    ? () {
                                  Navigator.of(context).pop();
                                  showSellerReportDialog(int.parse(p["seller_id"].toString()));
                                }
                                    : null,
                              ),
                              _miniChip("Status: ${p["status"] ?? "-"}"),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Description: ${(p["description"] ?? "-").toString().trim().isEmpty ? "-" : p["description"]}",
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  int _filteredUsersTotalOrders() {
    int total = 0;
    for (final u in _filteredUsers()) {
      total += ((u["total_orders"] ?? 0) as num).toInt();
    }
    return total;
  }

  double _filteredUsersTotalSpent() {
    double total = 0;
    for (final u in _filteredUsers()) {
      total += _d(u["total_spent"]);
    }
    return total;
  }

  int _filteredSellersTotalProducts() {
    int total = 0;
    for (final s in _filteredSellers()) {
      total += ((s["total_products"] ?? 0) as num).toInt();
    }
    return total;
  }

  int _filteredSellersTotalOrders() {
    int total = 0;
    for (final s in _filteredSellers()) {
      total += ((s["total_orders"] ?? 0) as num).toInt();
    }
    return total;
  }

  double _filteredSellersTotalRevenue() {
    double total = 0;
    for (final s in _filteredSellers()) {
      total += _d(s["total_revenue"]);
    }
    return total;
  }

  Future<void> downloadProductsPdf() async {
    final filteredProducts = _filteredProducts();
    if (filteredProducts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No products data to export")),
        );
      }
      return;
    }

    final pdf = pw.Document();

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _pdfCell("Product ID", bold: true),
          _pdfCell("Product Name", bold: true),
          _pdfCell("Seller ID", bold: true),
          _pdfCell("Price", bold: true),
          _pdfCell("Stock", bold: true),
          _pdfCell("Avg Rating", bold: true),
          _pdfCell("Reviews", bold: true),
          _pdfCell("Status", bold: true),
        ],
      ),
      ...filteredProducts.map((p) => pw.TableRow(children: [
        _pdfCell("${p["product_id"] ?? "-"}"),
        _pdfCell(_productName(p)),
        _pdfCell("${p["seller_id"] ?? "-"}"),
        _pdfCell("Rs. ${_money(p["price"])}"),
        _pdfCell("${_productStock(p)}"),
        _pdfCell(_d(p["avg_rating"]).toStringAsFixed(1)),
        _pdfCell("${p["review_count"] ?? 0}"),
        _pdfCell("${p["status"] ?? "-"}"),
      ])),
      pw.TableRow(children: [
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell("Avg Rating", bold: true),
        _pdfCell(_filteredProductsAverageRating().toStringAsFixed(1), bold: true),
        _pdfCell("Reviews", bold: true),
        _pdfCell("${_filteredProductsTotalReviews()}", bold: true),
      ]),
      pw.TableRow(children: [
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell(""),
        _pdfCell("Total Products", bold: true),
        _pdfCell("${filteredProducts.length}", bold: true),
      ]),
    ];

    final filename = "products_report_${range == "custom" ? "custom_range" : range}.pdf";

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text(
            "Products Report",
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Text("Date Range: ${_rangeLabel(range)}"),
          pw.SizedBox(height: 14),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: rows,
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute("download", filename)
      ..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("$filename downloaded")),
      );
    }
  }

  Future<void> downloadUsersPdf() async {
    final filteredUsers = _filteredUsers();
    if (filteredUsers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No users data to export")),
        );
      }
      return;
    }

    final pdf = pw.Document();
    final rows = <List<String>>[];
    for (final u in filteredUsers) {
      rows.add([
        "${u["user_id"] ?? "-"}",
        "${u["user_name"] ?? "-"}",
        "${u["total_orders"] ?? 0}",
        "Rs. ${_money(u["total_spent"])}",
      ]);
    }
    rows.add(["", "Total", "${_filteredUsersTotalOrders()}", "Rs. ${_money(_filteredUsersTotalSpent())}"]);

    final filename = "users_report_${range == "custom" ? "custom_range" : range}.pdf";
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text("Users Report", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text("Date Range: ${_rangeLabel(range)}"),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.0),
              1: const pw.FlexColumnWidth(2.8),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell("User ID", bold: true),
                  _pdfCell("User Name", bold: true),
                  _pdfCell("Total Orders", bold: true),
                  _pdfCell("Total Spent", bold: true),
                ],
              ),
              ...rows.map((r) => pw.TableRow(children: [
                _pdfCell(r[0], bold: r[1] == "Total"),
                _pdfCell(r[1], bold: r[1] == "Total"),
                _pdfCell(r[2], bold: r[1] == "Total"),
                _pdfCell(r[3], bold: r[1] == "Total"),
              ])),
            ],
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)..setAttribute("download", filename)..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$filename downloaded")));
    }
  }

  Future<void> downloadSellersPdf() async {
    final filteredSellers = _filteredSellers();
    if (filteredSellers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No sellers data to export")),
        );
      }
      return;
    }

    final pdf = pw.Document();
    final rows = <List<String>>[];
    for (final s in filteredSellers) {
      rows.add([
        "${s["seller_id"] ?? "-"}",
        "${s["seller_name"] ?? "-"}",
        "${s["total_products"] ?? 0}",
        "${s["total_orders"] ?? 0}",
        "Rs. ${_money(s["total_revenue"])}",
      ]);
    }
    rows.add(["", "Total", "${_filteredSellersTotalProducts()}", "${_filteredSellersTotalOrders()}", "Rs. ${_money(_filteredSellersTotalRevenue())}"]);

    final filename = "sellers_report_${range == "custom" ? "custom_range" : range}.pdf";
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Text("Sellers Report", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text("Date Range: ${_rangeLabel(range)}"),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.0),
              1: const pw.FlexColumnWidth(2.5),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.4),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _pdfCell("Seller ID", bold: true),
                  _pdfCell("Seller Name", bold: true),
                  _pdfCell("Products", bold: true),
                  _pdfCell("Orders", bold: true),
                  _pdfCell("Revenue", bold: true),
                ],
              ),
              ...rows.map((r) => pw.TableRow(children: [
                _pdfCell(r[0], bold: r[1] == "Total"),
                _pdfCell(r[1], bold: r[1] == "Total"),
                _pdfCell(r[2], bold: r[1] == "Total"),
                _pdfCell(r[3], bold: r[1] == "Total"),
                _pdfCell(r[4], bold: r[1] == "Total"),
              ])),
            ],
          ),
        ],
      ),
    );

    final Uint8List bytes = await pdf.save();
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)..setAttribute("download", filename)..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$filename downloaded")));
    }
  }

  Widget _searchField({
    required String hint,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required VoidCallback onClear,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
          onPressed: onClear,
          icon: const Icon(Icons.close),
        )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    List<Widget>? actions,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (actions != null) ...actions,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }

  Widget _clickableStatCard({
    required String title,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    bool clickable = false,
  }) {
    return InkWell(
      onTap: clickable ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: 210,
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black.withOpacity(0.06),
                  ),
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.65),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (clickable) ...[
                        const SizedBox(height: 6),
                        const Text(
                          "Click to view",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  BarChartData _barData(List<String> labels, List<double> values) {
    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      maxY: _maxY(values),
      barTouchData: BarTouchData(
        enabled: true,
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final label = labels[group.x.toInt()];
            return BarTooltipItem(
              "$label\n${rod.toY.toInt()}",
              const TextStyle(fontWeight: FontWeight.w700),
            );
          },
        ),
      ),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (v, meta) {
              if (v % 1 != 0) return const SizedBox.shrink();
              return Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 11),
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        topTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            getTitlesWidget: (value, meta) {
              final idx = value.toInt();
              if (idx < 0 || idx >= labels.length) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  labels[idx],
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: Colors.black.withOpacity(0.10)),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (value) => FlLine(
          color: Colors.black.withOpacity(0.06),
          strokeWidth: 1,
        ),
      ),
      barGroups: List.generate(values.length, (i) {
        return BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: values[i],
              width: 22,
              borderRadius: BorderRadius.circular(6),
              color: Colors.cyan,
            ),
          ],
        );
      }),
    );
  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _clickableMiniChip(String text, {VoidCallback? onTap}) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: enabled ? Colors.blue.withOpacity(0.08) : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: enabled ? Border.all(color: Colors.blue.withOpacity(0.25)) : null,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: enabled ? Colors.blue.shade700 : null,
            fontWeight: enabled ? FontWeight.w600 : FontWeight.normal,
            decoration: enabled ? TextDecoration.underline : TextDecoration.none,
          ),
        ),
      ),
    );
  }

  List<Color> _statusPalette() {
    return const [
      Color(0xFF4F46E5),
      Color(0xFF06B6D4),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFF14B8A6),
    ];
  }

  Widget _buildPieFromMap(Map<String, dynamic> data, {void Function(String label)? onLegendTap, String selectedLabel = ""}) {
    final entries = data.entries.where((e) => _d(e.value) > 0).toList();

    if (entries.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            "No data available",
            style: TextStyle(color: Colors.black.withOpacity(0.55)),
          ),
        ),
      );
    }

    final total = entries.fold<double>(0, (sum, e) => sum + _d(e.value));
    final colors = _statusPalette();

    return TweenAnimationBuilder<double>(
      key: ValueKey(entries.map((e) => '${e.key}:${e.value}').join('|')),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutBack,
      builder: (context, progress, _) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 450),
          opacity: progress.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 640;
                final isTablet = constraints.maxWidth < 980;
                final chartSize = isMobile ? 200.0 : (isTablet ? 220.0 : 250.0);
                final radius = isMobile ? 68.0 : 78.0;
                final centerSpace = isMobile ? 38.0 : 48.0;

                final chart = Container(
                  width: chartSize,
                  height: chartSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 4,
                      centerSpaceRadius: centerSpace,
                      startDegreeOffset: -90 + ((1 - progress) * 18),
                      pieTouchData: PieTouchData(enabled: false),
                      sections: List.generate(entries.length, (i) {
                        final rawValue = _d(entries[i].value);
                        final animatedValue = rawValue * progress;
                        final percent = total <= 0 ? 0 : (rawValue / total) * 100;
                        final showTitle = percent >= 8 || entries.length <= 3;
                        return PieChartSectionData(
                          color: colors[i % colors.length],
                          value: animatedValue <= 0 ? 0.0001 : animatedValue,
                          radius: radius + ((progress - 1) * -10),
                          title: showTitle ? '${percent.toStringAsFixed(0)}%' : '',
                          titlePositionPercentageOffset: 0.72,
                          badgeWidget: null,
                          titleStyle: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black26, blurRadius: 6),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                );

                final summary = Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.pie_chart_rounded, size: 18, color: Colors.black.withOpacity(0.65)),
                      const SizedBox(width: 8),
                      Text(
                        'Total ${total.toInt()} records',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );

                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: 12),
                    ...List.generate(entries.length, (i) {
                      final e = entries[i];
                      final value = _d(e.value);
                      final percent = total <= 0 ? 0 : (value / total) * 100;
                      final color = colors[i % colors.length];
                      final isSelected = selectedLabel.isNotEmpty && selectedLabel.toLowerCase() == e.key.toLowerCase();
                      return InkWell(
                        onTap: onLegendTap == null ? null : () => onLegendTap(e.key),
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(isSelected ? 0.16 : 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: color.withOpacity(isSelected ? 0.42 : 0.18)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.key,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${percent.toStringAsFixed(1)}% of total',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black.withOpacity(0.58),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                value.toInt().toString(),
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                );

                if (isMobile) {
                  return Column(
                    children: [
                      chart,
                      const SizedBox(height: 18),
                      legend,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(flex: 4, child: Center(child: chart)),
                    const SizedBox(width: 22),
                    Flexible(flex: 5, child: legend),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverview() {
    final totalUsers = (cards["total_users"] ?? 0).toString();
    final totalSellers = (cards["total_sellers"] ?? 0).toString();
    final totalProducts = (cards["total_products"] ?? 0).toString();
    final totalDeliveryStaff = (cards["total_delivery_staff"] ?? 0).toString();
    final totalOrders = (cards["total_orders"] ?? 0).toString();
    final revenue = _money(cards["revenue"]);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "Date Range:",
                style: TextStyle(color: Colors.black.withOpacity(0.70)),
              ),
              PopupMenuButton<String>(
                onSelected: _changeRange,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: "today", child: Text("Today")),
                  PopupMenuItem(value: "yesterday", child: Text("Yesterday")),
                  PopupMenuItem(value: "week", child: Text("Last 7 Days")),
                  PopupMenuItem(value: "month", child: Text("This Month")),
                  PopupMenuItem(value: "custom", child: Text("Custom Range")),
                ],
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black.withOpacity(0.12)),
                    color: Colors.white,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_rangeIcon(range), size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _rangeLabel(range),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
              ),
              if (range == "custom" && customStartDate != null && customEndDate != null)
                OutlinedButton.icon(
                  onPressed: _selectCustomDateRange,
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text("Change Dates"),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _clickableStatCard(
                title: "Total Users",
                value: totalUsers,
                icon: Icons.people,
                clickable: true,
                onTap: () {
                  setState(() {
                    currentView = "users";
                  });
                },
              ),
              _clickableStatCard(
                title: "Total Sellers",
                value: totalSellers,
                icon: Icons.store,
                clickable: true,
                onTap: () {
                  setState(() {
                    currentView = "sellers";
                  });
                },
              ),
              _clickableStatCard(
                title: "Total Delivery Staff",
                value: totalDeliveryStaff,
                icon: Icons.local_shipping,
                clickable: true,
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AllDeliveryStaffPage()));
                },
              ),
              _clickableStatCard(
                title: "Total Products",
                value: totalProducts,
                icon: Icons.inventory_2,
                clickable: true,
                onTap: () {
                  setState(() {
                    currentView = "products";
                  });
                },
              ),
              _clickableStatCard(
                title: "Orders (${_rangeLabel(range)})",
                value: totalOrders,
                icon: Icons.shopping_bag,
                clickable: true,
                onTap: () async {
                  await _openOrdersView(resetFilters: true);
                },
              ),
              _clickableStatCard(
                title: "Revenue (${_rangeLabel(range)})",
                value: "Rs. $revenue",
                icon: Icons.currency_rupee,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final chartWidth = isWide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

              final orderCard = SizedBox(
                width: chartWidth,
                child: _sectionCard(
                  title: "Orders by Status",
                  child: _buildPieFromMap(
                    orderStatusCounts,
                    selectedLabel: orderStatusFilter == "All" ? "" : orderStatusFilter,
                    onLegendTap: (label) async {
                      await _openOrdersView(orderStatus: label, paymentStatus: "All", revenueDay: "", resetFilters: false);
                    },
                  ),
                ),
              );

              final paymentCard = SizedBox(
                width: chartWidth,
                child: _sectionCard(
                  title: "Payments by Status",
                  child: _buildPieFromMap(
                    paymentStatusCounts,
                    selectedLabel: orderPaymentStatusFilter == "All" ? "" : orderPaymentStatusFilter,
                    onLegendTap: (label) async {
                      await _openOrdersView(paymentStatus: label, orderStatus: "All", revenueDay: "", resetFilters: false);
                    },
                  ),
                ),
              );

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [orderCard, paymentCard],
              );
            },
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Revenue by Day",
            child: revenueByDay.isEmpty
                ? Text(
              "No revenue data for selected range",
              style: TextStyle(color: Colors.black.withOpacity(0.60)),
            )
                : LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 720;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: revenueByDay.map((r) {
                    final day = (r["day"] ?? "").toString();
                    final total = _money(r["total"]);
                    final isSelectedDay = selectedRevenueDay.isNotEmpty && selectedRevenueDay == day;
                    return InkWell(
                      onTap: () async {
                        await _openOrdersView(revenueDay: day, orderStatus: "All", paymentStatus: "All", resetFilters: false);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: isCompact ? constraints.maxWidth : (constraints.maxWidth - 12) / 2,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isSelectedDay ? Colors.blue.withOpacity(0.08) : Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: isSelectedDay ? Colors.blue.withOpacity(0.30) : Colors.black.withOpacity(0.05)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.calendar_today, size: 18, color: Colors.blue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                day,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(
                              "Rs. $total",
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsersList() {
    final filteredUsers = _filteredUsers();
    final totalOrders = _filteredUsersTotalOrders();
    final totalSpent = _filteredUsersTotalSpent();

    final rows = <DataRow>[
      ...filteredUsers.map((u) => DataRow(cells: [
        DataCell(Text("${u["user_id"] ?? "-"}")),
        DataCell(
          InkWell(
            onTap: () => openUserReport((u["user_id"] ?? 0) as int),
            child: Text(
              "${u["user_name"] ?? "-"}",
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(Text("${u["user_email"] ?? "-"}")),
        DataCell(Text("${u["total_orders"] ?? 0}")),
        DataCell(Text("Rs. ${_money(u["total_spent"])}", style: const TextStyle(fontWeight: FontWeight.w600))),
      ])),
      DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(Text("")),
          const DataCell(Text("Total", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          const DataCell(Text("")),
          DataCell(Text("$totalOrders", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          DataCell(Text("Rs. ${_money(totalSpent)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    currentView = "overview";
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back"),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text("All Users Reports", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Users",
            actions: [
              ElevatedButton.icon(
                onPressed: filteredUsers.isEmpty ? null : downloadUsersPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download PDF"),
              ),
            ],
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _miniChip("Users: ${filteredUsers.length}"),
                    _miniChip("Orders: $totalOrders"),
                    _miniChip("Total Spent: Rs. ${_money(totalSpent)}"),
                  ],
                ),
                const SizedBox(height: 14),
                _searchField(
                  hint: "Search user by name, email, mobile or id",
                  controller: userSearchController,
                  onChanged: (value) {
                    setState(() {
                      userSearch = value;
                    });
                  },
                  onClear: () {
                    userSearchController.clear();
                    setState(() {
                      userSearch = "";
                    });
                  },
                ),
                const SizedBox(height: 14),
                if (filteredUsers.isEmpty)
                  const Text("No users found")
                else
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 28,
                          dataRowMinHeight: 52,
                          dataRowMaxHeight: 60,
                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                          columns: const [
                            DataColumn(label: Text("User ID", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("User Name", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Email", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Total Orders", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Total Spent", style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: rows,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellersList() {
    final filteredSellers = _filteredSellers();
    final totalProducts = _filteredSellersTotalProducts();
    final totalOrders = _filteredSellersTotalOrders();
    final totalRevenue = _filteredSellersTotalRevenue();

    final rows = <DataRow>[
      ...filteredSellers.map((s) => DataRow(cells: [
        DataCell(Text("${s["seller_id"] ?? "-"}")),
        DataCell(
          InkWell(
            onTap: () => openSellerReport((s["seller_id"] ?? 0) as int),
            child: Text(
              "${s["seller_name"] ?? "-"}",
              style: const TextStyle(
                color: Colors.blue,
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(Text("${s["seller_email"] ?? "-"}")),
        DataCell(Text("${s["total_products"] ?? 0}")),
        DataCell(Text("${s["total_orders"] ?? 0}")),
        DataCell(Text("Rs. ${_money(s["total_revenue"])}", style: const TextStyle(fontWeight: FontWeight.w600))),
      ])),
      DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(Text("")),
          const DataCell(Text("Total", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          const DataCell(Text("")),
          DataCell(Text("$totalProducts", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          DataCell(Text("$totalOrders", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          DataCell(Text("Rs. ${_money(totalRevenue)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
        ],
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    currentView = "overview";
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back"),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text("All Sellers Reports", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Sellers",
            actions: [
              ElevatedButton.icon(
                onPressed: filteredSellers.isEmpty ? null : downloadSellersPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download PDF"),
              ),
            ],
            child: Column(
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _miniChip("Sellers: ${filteredSellers.length}"),
                    _miniChip("Products: $totalProducts"),
                    _miniChip("Orders: $totalOrders"),
                    _miniChip("Revenue: Rs. ${_money(totalRevenue)}"),
                  ],
                ),
                const SizedBox(height: 14),
                _searchField(
                  hint: "Search seller by name, email, mobile or id",
                  controller: sellerSearchController,
                  onChanged: (value) {
                    setState(() {
                      sellerSearch = value;
                    });
                  },
                  onClear: () {
                    sellerSearchController.clear();
                    setState(() {
                      sellerSearch = "";
                    });
                  },
                ),
                const SizedBox(height: 14),
                if (filteredSellers.isEmpty)
                  const Text("No sellers found")
                else
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 28,
                          dataRowMinHeight: 52,
                          dataRowMaxHeight: 60,
                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade200),
                          columns: const [
                            DataColumn(label: Text("Seller ID", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Seller Name", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Email", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Products", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Orders", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Revenue", style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: rows,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    final filteredProducts = _filteredProducts();
    final totalStock = _filteredProductsTotalStock();
    final inStockCount = _filteredProductsInStockCount();
    final outOfStockCount = filteredProducts.length - inStockCount;
    final inventoryValue = _filteredProductsInventoryValue();
    final ratedProducts = filteredProducts.where((p) => _d(p["avg_rating"]) > 0).length;
    final totalReviews = filteredProducts.fold<int>(
      0,
          (sum, p) => sum + (int.tryParse((p["review_count"] ?? 0).toString()) ?? 0),
    );
    final avgRating = ratedProducts > 0
        ? filteredProducts
        .where((p) => _d(p["avg_rating"]) > 0)
        .fold<double>(0, (sum, p) => sum + _d(p["avg_rating"])) / ratedProducts
        : 0.0;
    final topProducts = _topProductsByStock();
    final stockLabels = topProducts
        .map((p) => _productName(p).length > 12
        ? "${_productName(p).substring(0, 12)}…"
        : _productName(p))
        .toList();
    final stockValues = topProducts.map((p) => _productStock(p).toDouble()).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    currentView = "overview";
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back"),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "All Products Reports",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 450),
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 18),
                  child: child,
                ),
              );
            },
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _clickableStatCard(
                      title: "Filtered Products",
                      value: filteredProducts.length.toString(),
                      icon: Icons.inventory_2_outlined,
                    ),
                    _clickableStatCard(
                      title: "Total Stock Units",
                      value: totalStock.toString(),
                      icon: Icons.warehouse_outlined,
                    ),
                    _clickableStatCard(
                      title: "In Stock",
                      value: inStockCount.toString(),
                      icon: Icons.check_circle_outline,
                    ),
                    _clickableStatCard(
                      title: "Out of Stock",
                      value: outOfStockCount.toString(),
                      icon: Icons.remove_shopping_cart_outlined,
                    ),
                    _clickableStatCard(
                      title: "Inventory Value",
                      value: "Rs. ${_money(inventoryValue)}",
                      icon: Icons.currency_rupee,
                    ),
                    _clickableStatCard(
                      title: "Avg Rating",
                      value: avgRating.toStringAsFixed(1),
                      icon: Icons.star_outline,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Products",
            actions: [
              ElevatedButton.icon(
                onPressed: filteredProducts.isEmpty ? null : downloadProductsPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download PDF"),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _miniChip("Auto refresh: every 15 sec"),
                    _miniChip("Stock Units: $totalStock"),
                    _miniChip("In Stock Products: $inStockCount"),
                    _miniChip("Inventory Value: Rs. ${_money(inventoryValue)}"),
                    _miniChip("Rated Products: $ratedProducts"),
                    _miniChip("Total Reviews: $totalReviews"),
                    _miniChip("Avg Rating: ${avgRating.toStringAsFixed(1)} ⭐"),
                  ],
                ),
                const SizedBox(height: 14),
                _searchField(
                  hint:
                  "Search by product id, product name, seller id, status, stock, price or rating",
                  controller: productSearchController,
                  onChanged: (value) {
                    setState(() {
                      productSearch = value;
                    });
                  },
                  onClear: () {
                    productSearchController.clear();
                    setState(() {
                      productSearch = "";
                    });
                  },
                ),
                const SizedBox(height: 14),
                if (filteredProducts.isEmpty)
                  const Text("No products found")
                else
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          columnSpacing: 28,
                          dataRowMinHeight: 54,
                          dataRowMaxHeight: 62,
                          headingRowColor:
                          WidgetStateProperty.all(Colors.grey.shade200),
                          columns: const [
                            DataColumn(label: Text("Product ID", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Product Name", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Seller ID", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Price", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Stock Qty", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Avg Rating", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Reviews", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Stock Status", style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text("Status", style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: [
                            ...filteredProducts.map(
                                  (p) => DataRow(
                                cells: [
                                  DataCell(Text("${p["product_id"] ?? "-"}")),
                                  DataCell(Text(_productName(p))),
                                  DataCell(Text("${p["seller_id"] ?? "-"}")),
                                  DataCell(Text("Rs. ${_money(p["price"])}")),
                                  DataCell(Text("${_productStock(p)}")),
                                  DataCell(Text("${_d(p["avg_rating"]).toStringAsFixed(1)} ⭐")),
                                  DataCell(Text("${p["review_count"] ?? 0}")),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: _productStock(p) > 0
                                            ? Colors.green.withOpacity(0.10)
                                            : Colors.red.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: _productStock(p) > 0
                                              ? Colors.green.withOpacity(0.25)
                                              : Colors.red.withOpacity(0.25),
                                        ),
                                      ),
                                      child: Text(
                                        _productStock(p) > 0 ? "Available" : "Out of Stock",
                                        style: TextStyle(
                                          color: _productStock(p) > 0 ? Colors.green.shade700 : Colors.red.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  DataCell(Text("${p["status"] ?? "-"}")),
                                ],
                              ),
                            ),
                            DataRow(
                              color: WidgetStateProperty.all(Colors.grey.shade100),
                              cells: [
                                const DataCell(Text("")),
                                const DataCell(Text("Total", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                const DataCell(Text("")),
                                DataCell(Text("Rs. ${_money(inventoryValue)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                DataCell(Text("$totalStock", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                DataCell(Text("${avgRating.toStringAsFixed(1)} ⭐", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                DataCell(Text("$totalReviews", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                DataCell(Text("$inStockCount / ${filteredProducts.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                DataCell(Text("${filteredProducts.length}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList() {
    final filteredOrders = _filteredOrders();

    double totalAmount = 0;
    for (final o in filteredOrders) {
      totalAmount += _d(o["amount"]);
    }

    final tableRows = <DataRow>[
      ...filteredOrders.map((o) {
        final orderId = o["order_id"];
        return DataRow(
          cells: [
            DataCell(Text("${o["order_id"] ?? "-"}")),
            DataCell(
              InkWell(
                onTap: orderId != null ? () => _openProductsForOrderRow(o) : null,
                child: Text(
                  _productName(o),
                  style: const TextStyle(
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            DataCell(
              InkWell(
                onTap: o["user_id"] != null ? () => showUserReportDialog(int.parse(o["user_id"].toString())) : null,
                child: Text(
                  "${o["user_id"] ?? "-"}",
                  style: TextStyle(
                    color: o["user_id"] != null ? Colors.blue : null,
                    decoration: o["user_id"] != null ? TextDecoration.underline : TextDecoration.none,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            DataCell(
              InkWell(
                onTap: o["seller_id"] != null ? () => showSellerReportDialog(int.parse(o["seller_id"].toString())) : null,
                child: Text(
                  "${o["seller_id"] ?? "-"}",
                  style: TextStyle(
                    color: o["seller_id"] != null ? Colors.blue : null,
                    decoration: o["seller_id"] != null ? TextDecoration.underline : TextDecoration.none,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            DataCell(Text("${o["order_status"] ?? "-"}")),
            DataCell(Text("${o["payment_status"] ?? "-"}")),
            DataCell(
              Text(
                "Rs. ${_money(o["amount"])}",
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      }),

      // LAST TOTAL ROW
      DataRow(
        cells: [
          const DataCell(Text("")),
          const DataCell(Text("")),
          const DataCell(Text("")),
          const DataCell(Text("")),
          const DataCell(Text("")),
          const DataCell(
            Text(
              "Total Amount",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          DataCell(
            Text(
              "Rs. ${_money(totalAmount)}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    currentView = "overview";
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back"),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "All Orders Reports",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _filteredOrders().isEmpty ? null : downloadOrdersPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download PDF"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Orders",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _searchField(
                  hint: "Search by order id, product name, user id, seller id or amount",
                  controller: orderSearchController,
                  onChanged: (value) {
                    setState(() {
                      orderSearch = value;
                    });
                  },
                  onClear: () {
                    orderSearchController.clear();
                    setState(() {
                      orderSearch = "";
                    });
                  },
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: orderStatusFilter,
                        decoration: const InputDecoration(
                          labelText: "Order Status",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: "All", child: Text("All")),
                          DropdownMenuItem(value: "Pending", child: Text("Pending")),
                          DropdownMenuItem(value: "Confirmed", child: Text("Confirmed")),
                          DropdownMenuItem(value: "Packed", child: Text("Packed")),
                          DropdownMenuItem(value: "OutForDelivery", child: Text("Out For Delivery")),
                          DropdownMenuItem(value: "Delivered", child: Text("Delivered")),
                          DropdownMenuItem(value: "Cancelled", child: Text("Cancelled")),
                        ],
                        onChanged: (value) {
                          setState(() {
                            orderStatusFilter = value ?? "All";
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        initialValue: orderPaymentStatusFilter,
                        decoration: const InputDecoration(
                          labelText: "Payment Status",
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: "All", child: Text("All")),
                          DropdownMenuItem(value: "Paid", child: Text("Paid")),
                          DropdownMenuItem(value: "Pending", child: Text("Pending")),
                          DropdownMenuItem(value: "Failed", child: Text("Failed")),
                        ],
                        onChanged: (value) {
                          setState(() {
                            orderPaymentStatusFilter = value ?? "All";
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (filteredOrders.isEmpty)
                  const Text("No orders found")
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 40,
                      headingRowColor: WidgetStateProperty.all(
                        Colors.grey.shade200,
                      ),
                      columns: const [
                        DataColumn(label: Text("Order ID")),
                        DataColumn(label: Text("Product Name")),
                        DataColumn(label: Text("User ID")),
                        DataColumn(label: Text("Seller ID")),
                        DataColumn(label: Text("Order Status")),
                        DataColumn(label: Text("Payment Status")),
                        DataColumn(label: Text("Amount")),
                      ],
                      rows: tableRows,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildDetail() {
    final detail = selectedDetail;

    if (detailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (detail == null) {
      return const Center(child: Text("No detail selected"));
    }

    final isUser = selectedType == "user";
    final isSeller = selectedType == "seller";
    final isOrder = selectedType == "order";

    if (isOrder) {
      final profile = Map<String, dynamic>.from(detail["profile"] ?? {});
      final stats = Map<String, dynamic>.from(detail["stats"] ?? {});

      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      currentView = "orders";
                      selectedDetail = null;
                    });
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text("Back"),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "Order Report Details",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: downloadCurrentPdf,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text("Download PDF"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: "Order Summary",
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _clickableStatCard(
                    title: "Order ID",
                    value: "${profile["order_id"] ?? ""}",
                    icon: Icons.receipt_long,
                    onTap: () {},
                  ),
                  _clickableStatCard(
                    title: "Amount",
                    value: "Rs. ${_money(stats["total_amount"])}",
                    icon: Icons.currency_rupee,
                    onTap: () {},
                  ),
                  _clickableStatCard(
                    title: "Order Status",
                    value: "${stats["order_status"] ?? ""}",
                    icon: Icons.local_shipping,
                    onTap: () {},
                  ),
                  _clickableStatCard(
                    title: "Payment Status",
                    value: "${stats["payment_status"] ?? ""}",
                    icon: Icons.payments,
                    onTap: () {},
                  ),
                  _clickableStatCard(
                    title: "Payment Method",
                    value: "${stats["payment_method"] ?? ""}",
                    icon: Icons.account_balance_wallet,
                    onTap: () {},
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _sectionCard(
              title: "Order Details",
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Order Date: ${_date(profile["order_date"])}"),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: profile["user_id"] != null ? () => showUserReportDialog(int.parse(profile["user_id"].toString())) : null,
                    child: Text(
                      "User ID: ${profile["user_id"] ?? "-"}",
                      style: TextStyle(
                        color: profile["user_id"] != null ? Colors.blue : null,
                        decoration: profile["user_id"] != null ? TextDecoration.underline : TextDecoration.none,
                      ),
                    ),
                  ),
                  Text("User Name: ${profile["user_name"] ?? "-"}"),
                  Text("User Email: ${profile["user_email"] ?? "-"}"),
                  Text("User Mobile: ${profile["user_mobile"] ?? "-"}"),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: profile["seller_id"] != null ? () => showSellerReportDialog(int.parse(profile["seller_id"].toString())) : null,
                    child: Text(
                      "Seller ID: ${profile["seller_id"] ?? "-"}",
                      style: TextStyle(
                        color: profile["seller_id"] != null ? Colors.blue : null,
                        decoration: profile["seller_id"] != null ? TextDecoration.underline : TextDecoration.none,
                      ),
                    ),
                  ),
                  Text("Seller Name: ${profile["seller_name"] ?? "-"}"),
                  Text("Seller Email: ${profile["seller_email"] ?? "-"}"),
                  Text("Seller Mobile: ${profile["seller_mobile"] ?? "-"}"),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: "Products In This Order",
              actions: [
                if ((detail["products"] as List?)?.isNotEmpty ?? false)
                  TextButton.icon(
                    onPressed: () => openOrderProducts(int.parse((profile["order_id"] ?? 0).toString())),
                    icon: const Icon(Icons.visibility),
                    label: const Text("Open Full View"),
                  ),
              ],
              child: Builder(
                builder: (_) {
                  final orderProducts = List<dynamic>.from(detail["products"] ?? []);
                  if (orderProducts.isEmpty) {
                    return const Text("No product details found for this order.");
                  }

                  return Column(
                    children: orderProducts.map((p) {
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _productName(p),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _miniChip("Product ID: ${p["product_id"] ?? "-"}"),
                                if (p["ordered_qty"] != null) _miniChip("Qty: ${p["ordered_qty"]}"),
                                if (p["ordered_price"] != null) _miniChip("Total Price: Rs. ${_money(p["ordered_price"])}"),
                                if (p["ordered_total"] != null) _miniChip("Item Total: Rs. ${_money(p["ordered_total"])}"),
                                _miniChip("Price: Rs. ${_money(p["price"])}"),
                                _miniChip("Stock: ${p["stock"] ?? "-"}"),
                                _miniChip("Brand: ${p["brand"] ?? "-"}"),
                                _miniChip("Category ID: ${p["category_id"] ?? "-"}"),
                                _miniChip("Seller ID: ${p["seller_id"] ?? "-"}"),
                                _miniChip("Status: ${p["status"] ?? "-"}"),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              "Description: ${(p["description"] ?? "-").toString().trim().isEmpty ? "-" : p["description"]}",
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    final profile = Map<String, dynamic>.from(detail["profile"] ?? {});
    final stats = Map<String, dynamic>.from(detail["stats"] ?? {});
    final orderCounts = Map<String, dynamic>.from(
      detail["order_status_counts"] ?? {},
    );
    final paymentCounts = Map<String, dynamic>.from(
      detail["payment_status_counts"] ?? {},
    );
    final paymentMethods = Map<String, dynamic>.from(
      detail["payment_method_counts"] ?? {},
    );
    final recentOrders = List<dynamic>.from(detail["recent_orders"] ?? []);

    final orderLabels = orderCounts.keys.toList();
    final orderValues = orderLabels.map((e) => _d(orderCounts[e])).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    currentView = isUser ? "users" : "sellers";
                    selectedDetail = null;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Back"),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isUser ? "User Report Details" : "Seller Report Details",
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: downloadCurrentPdf,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Download PDF"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _sectionCard(
            title: "Profile",
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Name: ${profile["name"] ?? "-"}",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text("Email: ${profile["email"] ?? "-"}"),
                const SizedBox(height: 6),
                Text("Mobile: ${profile["mobile"] ?? "-"}"),
                const SizedBox(height: 6),
                Text("Joined: ${_date(profile["registration_at"])}"),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (isUser) ...[
                _clickableStatCard(
                  title: "Total Orders",
                  value: "${stats["total_orders"] ?? 0}",
                  icon: Icons.shopping_bag,
                  onTap: () {},
                ),
                _clickableStatCard(
                  title: "Total Spent",
                  value: "Rs. ${_money(stats["total_spent"])}",
                  icon: Icons.currency_rupee,
                  onTap: () {},
                ),
              ] else ...[
                _clickableStatCard(
                  title: "Total Products",
                  value: "${stats["total_products"] ?? 0}",
                  icon: Icons.inventory_2,
                  onTap: () {},
                ),
                _clickableStatCard(
                  title: "Total Revenue",
                  value: "Rs. ${_money(stats["total_revenue"])}",
                  icon: Icons.currency_rupee,
                  onTap: () {},
                ),
                _clickableStatCard(
                  title: "Total Orders",
                  value: "${stats["total_orders"] ?? 0}",
                  icon: Icons.shopping_bag,
                  onTap: () {},
                ),
              ],
              _clickableStatCard(
                title: "Avg Order Value",
                value: "Rs. ${_money(stats["avg_order_value"])}",
                icon: Icons.analytics,
                onTap: () {},
              ),
              _clickableStatCard(
                title: "Paid Orders",
                value: "${stats["paid_orders"] ?? 0}",
                icon: Icons.check_circle,
                onTap: () {},
              ),
              _clickableStatCard(
                title: "Pending Payments",
                value: "${stats["pending_payments"] ?? 0}",
                icon: Icons.hourglass_bottom,
                onTap: () {},
              ),
              _clickableStatCard(
                title: "Failed Payments",
                value: "${stats["failed_payments"] ?? 0}",
                icon: Icons.cancel,
                onTap: () {},
              ),
              _clickableStatCard(
                title: "Preferred Payment",
                value: "${stats["preferred_payment_method"] ?? "N/A"}",
                icon: Icons.payments,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Order Status Breakdown",
            child: _buildPieFromMap(orderCounts),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Payment Status Breakdown",
            child: SizedBox(
              height: 280,
              child: _buildPieFromMap(paymentCounts),
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Payment Method Usage",
            child: SizedBox(
              height: 280,
              child: _buildPieFromMap(paymentMethods),
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: "Recent Orders",
            child: recentOrders.isEmpty
                ? const Text("No recent orders")
                : Column(
              children: recentOrders.map((o) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text("${o["order_id"] ?? ""}"),
                    ),
                    title:
                    Text("Amount: Rs. ${_money(o["total_amount"])}"),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Date: ${_date(o["order_date"])}"),
                        Text("Order Status: ${o["order_status"] ?? "-"}"),
                        Text(
                          "Payment Status: ${o["payment_status"] ?? "-"}",
                        ),
                        Text(
                          "Payment Method: ${o["payment_method"] ?? "-"}",
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = "Reports";

    if (currentView == "users") {
      title = "Users Reports";
    } else if (currentView == "sellers") {
      title = "Sellers Reports";
    } else if (currentView == "products") {
      title = "Products Reports";
    } else if (currentView == "orders") {
      title = "Orders Reports";
    } else if (currentView == "detail") {
      title = "Detailed Report";
    }

    Widget body;

    if (loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (currentView == "users") {
      body = _buildUsersList();
    } else if (currentView == "sellers") {
      body = _buildSellersList();
    } else if (currentView == "products") {
      body = _buildProductsList();
    } else if (currentView == "orders") {
      body = _buildOrdersList();
    } else if (currentView == "detail") {
      body = _buildDetail();
    } else {
      body = _buildOverview();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: loading ? null : loadAllReports,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}