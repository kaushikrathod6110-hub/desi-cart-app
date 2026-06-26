import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:my_app/api_config.dart';
import '../screens/login_page.dart';
import '../screens/token_storage.dart';
import 'my_products_page.dart';
import 'order.dart';

class SellerReportsPage extends StatefulWidget {
  const SellerReportsPage({super.key});

  @override
  State<SellerReportsPage> createState() => _SellerReportsPageState();
}

class _SellerReportsPageState extends State<SellerReportsPage> {
  bool isLoading = true;
  String errorMessage = '';

  String range = 'custom';
  DateTime? customStartDate;
  DateTime? customEndDate;

  Map<String, dynamic> profile = {};
  Map<String, dynamic> cards = {};
  Map<String, dynamic> orderStatusCounts = {};
  Map<String, dynamic> paymentStatusCounts = {};
  Map<String, dynamic> paymentMethodCounts = {};
  List<dynamic> revenueByDay = [];
  List<dynamic> mostSoldProducts = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    customStartDate = DateTime(now.year, now.month - 1, 1);
    customEndDate = now;
    fetchReport();
  }

  Future<String?> _getToken() async {
    final storage = TokenStorage();
    return await storage.getAccessToken();
  }

  String _formatApiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Uri _buildUri() {
    final params = <String, String>{};

    if (range == 'custom' && customStartDate != null && customEndDate != null) {
      params['start_date'] = _formatApiDate(customStartDate!);
      params['end_date'] = _formatApiDate(customEndDate!);
    } else {
      params['range'] = range;
    }

    return ApiConfig.uri('/api/seller/reports/summary', queryParameters: params);
  }

  Future<void> fetchReport() async {
    setState(() {
      isLoading = true;
      errorMessage = '';
    });

    try {
      final token = await _getToken();

      if (token == null || token.isEmpty) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
        );
        return;
      }

      final response = await http.get(
        _buildUri(),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          profile = Map<String, dynamic>.from(data['profile'] ?? {});
          cards = Map<String, dynamic>.from(data['cards'] ?? {});
          orderStatusCounts =
          Map<String, dynamic>.from(data['order_status_counts'] ?? {});
          paymentStatusCounts =
          Map<String, dynamic>.from(data['payment_status_counts'] ?? {});
          paymentMethodCounts =
          Map<String, dynamic>.from(data['payment_method_counts'] ?? {});
          revenueByDay = List<dynamic>.from(data['revenue_by_day'] ?? []);
          mostSoldProducts =
          List<dynamic>.from(data['most_sold_products'] ?? []);
          isLoading = false;
        });
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
        setState(() {
          errorMessage = data['message'] ?? 'Failed to load reports';
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: $e';
        isLoading = false;
      });
    }
  }

  double _d(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _money(dynamic value) => _d(value).toStringAsFixed(2);

  String _date(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    if (text.isEmpty) return '-';
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  String _displayRangeLabel() {
    if (range == 'custom' &&
        customStartDate != null &&
        customEndDate != null) {
      return '${_formatApiDate(customStartDate!)} to ${_formatApiDate(customEndDate!)}';
    }
    switch (range) {
      case 'today':
        return 'Today';
      case 'yesterday':
        return 'Yesterday';
      case 'week':
        return 'This Week';
      case 'month':
        return 'This Month';
      default:
        return 'Custom';
    }
  }

  Future<void> _changeRange(String value) async {
    if (value == 'custom') {
      final now = DateTime.now();

      final start = await showDatePicker(
        context: context,
        initialDate: customStartDate ?? now.subtract(const Duration(days: 30)),
        firstDate: DateTime(2020),
        lastDate: now,
      );
      if (start == null || !mounted) return;

      final end = await showDatePicker(
        context: context,
        initialDate: customEndDate ?? now,
        firstDate: start,
        lastDate: now,
      );
      if (end == null || !mounted) return;

      setState(() {
        range = 'custom';
        customStartDate = start;
        customEndDate = end;
      });
      await fetchReport();
      return;
    }

    setState(() {
      range = value;
      customStartDate = null;
      customEndDate = null;
    });
    await fetchReport();
  }

  Widget _statsCard({
    required String title,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFFE3F2FD),
            child: Icon(icon, color: Colors.black, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: child,
      ),
    );
  }

  List<PieChartSectionData> _pieSections(Map<String, dynamic> data) {
    final entries = data.entries.where((e) => _d(e.value) > 0).toList();

    if (entries.isEmpty) {
      return [
        PieChartSectionData(
          value: 1,
          title: 'No Data',
          radius: 82,
          color: Colors.grey,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ];
    }

    final colors = <Color>[
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.indigo,
      Colors.brown,
    ];

    return List.generate(entries.length, (index) {
      final entry = entries[index];
      return PieChartSectionData(
        value: _d(entry.value),
        title: '${entry.key}\n${entry.value}',
        radius: 82,
        color: colors[index % colors.length],
        titleStyle: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      );
    });
  }

  Widget _pieCard(String title, Map<String, dynamic> data) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 34,
                  sectionsSpace: 3,
                  sections: _pieSections(data),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mostSoldProductsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Most Sold Products',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (mostSoldProducts.isEmpty)
              const Text('No sold products found in selected range.')
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingRowColor:
                  WidgetStatePropertyAll(Colors.grey.shade200),
                  columns: const [
                    DataColumn(label: Text('Product ID')),
                    DataColumn(label: Text('Product Name')),
                    DataColumn(label: Text('Sold Qty')),
                    DataColumn(label: Text('Revenue')),
                  ],
                  rows: mostSoldProducts.map((product) {
                    return DataRow(
                      cells: [
                        DataCell(Text('${product["product_id"] ?? "-"}')),
                        DataCell(Text('${product["product_name"] ?? "-"}')),
                        DataCell(Text('${product["sold_qty"] ?? 0}')),
                        DataCell(Text('Rs. ${_money(product["revenue"])}')),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _revenueCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revenue By Day',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (revenueByDay.isEmpty)
              const Text('No revenue data found.')
            else
              Column(
                children: revenueByDay.map((row) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE3F2FD),
                      child: Icon(Icons.calendar_today_outlined,
                          color: Colors.black),
                    ),
                    title: Text(_date(row['day'])),
                    subtitle: Text('Revenue: Rs. ${_money(row['total'])}'),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadPdf() async {
    final pdf = pw.Document();

    pw.Widget buildSectionMap(String title, Map<String, dynamic> data) {
      if (data.isEmpty) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('No data'),
          ],
        );
      }

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          ...data.entries.map(
                (e) => pw.Text('${e.key}: ${e.value}'),
          ),
        ],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'Seller Reports',
            style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Seller: ${(profile['name'] ?? 'Seller').toString()}'),
          pw.Text('Email: ${(profile['email'] ?? '-').toString()}'),
          pw.Text('Range: ${_displayRangeLabel()}'),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            children: [
              pw.TableRow(children: [
                _pdfCell('Total Products'),
                _pdfCell('${cards["total_products"] ?? 0}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Total Orders'),
                _pdfCell('${cards["total_orders"] ?? 0}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Revenue'),
                _pdfCell('Rs. ${_money(cards["total_revenue"])}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Average Order'),
                _pdfCell('Rs. ${_money(cards["avg_order_value"])}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Paid Orders'),
                _pdfCell('${cards["paid_orders"] ?? 0}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Pending Payments'),
                _pdfCell('${cards["pending_payments"] ?? 0}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Failed Payments'),
                _pdfCell('${cards["failed_payments"] ?? 0}'),
              ]),
              pw.TableRow(children: [
                _pdfCell('Preferred Payment'),
                _pdfCell('${cards["preferred_payment_method"] ?? 'N/A'}'),
              ]),
            ],
          ),
          pw.SizedBox(height: 16),
          buildSectionMap('Order Status Breakdown', orderStatusCounts),
          pw.SizedBox(height: 12),
          buildSectionMap('Payment Status Breakdown', paymentStatusCounts),
          pw.SizedBox(height: 12),
          buildSectionMap('Payment Method Breakdown', paymentMethodCounts),
          pw.SizedBox(height: 16),
          pw.Text(
            'Most Sold Products',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (mostSoldProducts.isEmpty)
            pw.Text('No sold products found in selected range.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400),
              children: [
                pw.TableRow(
                  decoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _pdfCell('Product ID', bold: true),
                    _pdfCell('Product Name', bold: true),
                    _pdfCell('Sold Qty', bold: true),
                    _pdfCell('Revenue', bold: true),
                  ],
                ),
                ...mostSoldProducts.map((product) {
                  return pw.TableRow(
                    children: [
                      _pdfCell('${product["product_id"] ?? "-"}'),
                      _pdfCell('${product["product_name"] ?? "-"}'),
                      _pdfCell('${product["sold_qty"] ?? 0}'),
                      _pdfCell('Rs. ${_money(product["revenue"])}'),
                    ],
                  );
                }),
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Revenue By Day',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (revenueByDay.isEmpty)
            pw.Text('No revenue data found.')
          else
            ...revenueByDay.map(
                  (row) =>
                  pw.Text('${_date(row["day"])}: Rs. ${_money(row["total"])}'),
            ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statCards = [
      _statsCard(
        title: 'Total Products',
        value: '${cards["total_products"] ?? 0}',
        icon: Icons.inventory_2_outlined,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyProductsPage()),
          );
        },
      ),
      _statsCard(
        title: 'Total Orders',
        value: '${cards["total_orders"] ?? 0}',
        icon: Icons.shopping_bag_outlined,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OrdersPage()),
          );
        },
      ),
      _statsCard(
        title: 'Revenue',
        value: 'Rs. ${_money(cards["total_revenue"])}',
        icon: Icons.currency_rupee,
      ),
      _statsCard(
        title: 'Avg Order',
        value: 'Rs. ${_money(cards["avg_order_value"])}',
        icon: Icons.analytics_outlined,
      ),
      _statsCard(
        title: 'Paid Orders',
        value: '${cards["paid_orders"] ?? 0}',
        icon: Icons.check_circle_outline,
      ),
      _statsCard(
        title: 'Pending',
        value: '${cards["pending_payments"] ?? 0}',
        icon: Icons.hourglass_bottom,
      ),
      _statsCard(
        title: 'Failed',
        value: '${cards["failed_payments"] ?? 0}',
        icon: Icons.cancel_outlined,
      ),
      _statsCard(
        title: 'Preferred Payment',
        value: '${cards["preferred_payment_method"] ?? "N/A"}',
        icon: Icons.payments_outlined,
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2196F3),
        title: const Text(
          'Seller Reports',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            tooltip: 'Download PDF',
            onPressed: _downloadPdf,
            icon: const Icon(
              Icons.picture_as_pdf_outlined,
              color: Colors.black,
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage.isNotEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      )
          : RefreshIndicator(
        onRefresh: fetchReport,
        child: LayoutBuilder(
          builder: (context, constraints) {
            int crossAxisCount = 2;
            double childAspectRatio = 2.0;

            if (constraints.maxWidth >= 1300) {
              crossAxisCount = 4;
              childAspectRatio = 3.2;
            } else if (constraints.maxWidth >= 900) {
              crossAxisCount = 3;
              childAspectRatio = 2.8;
            } else if (constraints.maxWidth >= 600) {
              crossAxisCount = 2;
              childAspectRatio = 2.5;
            } else if (constraints.maxWidth < 380) {
              crossAxisCount = 2;
              childAspectRatio = 1.7;
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${profile["name"] ?? "Seller"}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text('Email: ${profile["email"] ?? "-"}'),
                        Text('Mobile: ${profile["mobile"] ?? "-"}'),
                        Text(
                            'Joined: ${_date(profile["registration_at"])}'),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            value: range,
                            decoration: const InputDecoration(
                              labelText: 'Date Range',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'today',
                                child: Text('Today'),
                              ),
                              DropdownMenuItem(
                                value: 'yesterday',
                                child: Text('Yesterday'),
                              ),
                              DropdownMenuItem(
                                value: 'week',
                                child: Text('This Week'),
                              ),
                              DropdownMenuItem(
                                value: 'month',
                                child: Text('This Month'),
                              ),
                              DropdownMenuItem(
                                value: 'custom',
                                child: Text('Custom'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _changeRange(value);
                              }
                            },
                          ),
                        ),
                        if (range == 'custom' &&
                            customStartDate != null &&
                            customEndDate != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Selected: ${_displayRangeLabel()}',
                            style: const TextStyle(
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: statCards.length,
                  gridDelegate:
                  SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: childAspectRatio,
                  ),
                  itemBuilder: (context, index) => statCards[index],
                ),
                const SizedBox(height: 16),
                _mostSoldProductsCard(),
                const SizedBox(height: 16),
                _pieCard('Order Status Breakdown', orderStatusCounts),
                const SizedBox(height: 16),
                _pieCard(
                    'Payment Status Breakdown', paymentStatusCounts),
                const SizedBox(height: 16),
                _pieCard(
                    'Payment Method Breakdown', paymentMethodCounts),
                const SizedBox(height: 16),
                _revenueCard(),
              ],
            );
          },
        ),
      ),
    );
  }
}