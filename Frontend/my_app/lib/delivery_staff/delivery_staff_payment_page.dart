import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'delivery_staff_widgets.dart';

class DeliveryStaffPaymentPage extends StatefulWidget {
  const DeliveryStaffPaymentPage({super.key});

  @override
  State<DeliveryStaffPaymentPage> createState() => _DeliveryStaffPaymentPageState();
}

class _DeliveryStaffPaymentPageState extends State<DeliveryStaffPaymentPage> {
  bool isLoading = true;
  Map<String, dynamic> summary = {};
  List<dynamic> orders = [];
  DateTimeRange? customRange;

  @override
  void initState() {
    super.initState();
    loadPayments();
  }

  Future<String?> _token() async => TokenStorage().getAccessToken();

  String _formatApiDate(DateTime value) {
    final d = value.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  String _formatRange(DateTimeRange range) {
    String f(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    return '${f(range.start)} to ${f(range.end)}';
  }

  Future<void> loadPayments() async {
    setState(() => isLoading = true);
    try {
      final token = await _token();
      final query = <String, String>{'filter': 'delivered'};
      if (customRange != null) {
        query['start_date'] = _formatApiDate(customRange!.start);
        query['end_date'] = _formatApiDate(customRange!.end);
      }
      final response = await http.get(
        ApiConfig.uri('/api/delivery-staff/my-orders', queryParameters: query),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          orders = List<dynamic>.from(data['orders'] ?? []);
          summary = Map<String, dynamic>.from(data['summary'] ?? {});
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to load payment details');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1),
      initialDateRange: customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked == null) return;
    setState(() => customRange = picked);
    await loadPayments();
  }

  Future<void> clearCustomRange() async {
    setState(() => customRange = null);
    await loadPayments();
  }

  Map<String, dynamic> _section(String key) => Map<String, dynamic>.from(summary[key] ?? {});

  @override
  Widget build(BuildContext context) {
    final today = _section('today');
    final month = _section('this_month');
    final custom = _section('custom');

    final grouped = <String, Map<String, dynamic>>{};
    for (final raw in orders) {
      final item = Map<String, dynamic>.from(raw);
      final key = item['order_id'].toString();
      grouped.putIfAbsent(key, () => item);
    }
    final paymentOrders = grouped.values.toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF7F7FB),
        foregroundColor: Colors.black,
        title: const Text('Payment Details', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                deliverySoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Payment & Earnings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          ),
                          OutlinedButton.icon(
                            onPressed: pickCustomRange,
                            icon: const Icon(Icons.date_range),
                            label: const Text('Custom Range'),
                          ),
                          if (customRange != null) ...[
                            const SizedBox(width: 8),
                            IconButton(onPressed: clearCustomRange, icon: const Icon(Icons.close)),
                          ],
                        ],
                      ),
                      if (customRange != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text('Selected: ${_formatRange(customRange!)}', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 14),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isMobile = constraints.maxWidth < 700;
                          final itemWidth = isMobile ? (constraints.maxWidth - 12) / 2 : 320.0;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              SizedBox(width: itemWidth, child: deliverySummaryStatCard(title: 'Today Earning', value: '₹${formatMoney(today['total_earning'] ?? 0)}', color: Colors.green, icon: Icons.today)),
                              SizedBox(width: itemWidth, child: deliverySummaryStatCard(title: 'Today Delivered', value: '${today['delivered_orders'] ?? 0} order(s)', color: Colors.blue, icon: Icons.local_shipping)),
                              SizedBox(width: itemWidth, child: deliverySummaryStatCard(title: 'This Month Earning', value: '₹${formatMoney(month['total_earning'] ?? 0)}', color: Colors.deepPurple, icon: Icons.calendar_month)),
                              SizedBox(width: itemWidth, child: deliverySummaryStatCard(title: 'This Month COD', value: '₹${formatMoney(month['cod_collected'] ?? 0)}', color: Colors.orange, icon: Icons.payments)),
                              SizedBox(width: itemWidth, child: deliverySummaryStatCard(title: customRange != null ? 'Custom Earning' : 'All Matching Earning', value: '₹${formatMoney(custom['total_earning'] ?? 0)}', color: Colors.teal, icon: Icons.account_balance_wallet)),
                              SizedBox(width: itemWidth, child: deliverySummaryStatCard(title: customRange != null ? 'Custom COD' : 'Matching COD Collected', value: '₹${formatMoney(custom['cod_collected'] ?? 0)}', color: Colors.redAccent, icon: Icons.currency_rupee)),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                deliverySectionTitle('Delivered Payment Orders', subtitle: 'All delivered orders with earning and payment details'),
                const SizedBox(height: 12),
                if (paymentOrders.isEmpty)
                  deliverySoftCard(child: const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No payment records found'))))
                else
                  ...paymentOrders.map((item) {
                    final earningAmount = double.tryParse((item['earning_amount'] ?? 0).toString()) ?? 0;
                    return deliverySoftCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Order #${item['order_id']}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text('Delivered: ${formatDateTimeValue(item['delivered_at'] ?? item['order_date'])}', style: const TextStyle(color: Colors.black54)),
                                  ],
                                ),
                              ),
                              deliveryStatusChip((item['payment_status'] ?? '-').toString()),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              deliverySummaryStatCard(title: 'Order Amount', value: '₹${formatMoney(item['total_amount'] ?? 0)}', color: Colors.blue, icon: Icons.shopping_bag),
                              deliverySummaryStatCard(title: 'Your Earning', value: '₹${formatMoney(earningAmount)}', color: Colors.green, icon: Icons.currency_rupee),
                              deliverySummaryStatCard(title: 'Payment Method', value: (item['payment_method'] ?? '-').toString(), color: Colors.orange, icon: Icons.payments),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}