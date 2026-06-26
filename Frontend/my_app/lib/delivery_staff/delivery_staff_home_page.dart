import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/screens/login_page.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/delivery_staff/delivery_staff_dashboard_page.dart';
import 'package:my_app/delivery_staff/delivery_staff_available_orders_page.dart';
import 'package:my_app/delivery_staff/delivery_staff_my_orders_page.dart';
import 'package:my_app/delivery_staff/delivery_staff_order_details_page.dart';
import 'package:my_app/delivery_staff/delivery_staff_profile_page.dart';
import 'package:my_app/delivery_staff/delivery_staff_payment_page.dart';
import 'package:my_app/api_config.dart';

class DeliveryStaffHomePage extends StatefulWidget {
  const DeliveryStaffHomePage({super.key});

  @override
  State<DeliveryStaffHomePage> createState() => _DeliveryStaffHomePageState();
}

class _DeliveryStaffHomePageState extends State<DeliveryStaffHomePage> {
  int selectedIndex = 0;

  bool dashboardLoading = true;
  bool availableLoading = true;
  bool myOrdersLoading = true;
  bool detailLoading = false;

  bool showOrderDetails = false;

  Map<String, dynamic>? dashboardData;
  Map<String, dynamic> myOrdersSummary = {};
  List<dynamic> availableOrders = [];
  List<dynamic> myOrders = [];
  Map<String, dynamic>? selectedOrder;

  String myOrdersFilter = 'active';
  String availableSearch = '';
  String myOrdersSearch = '';
  DateTimeRange? myOrdersCustomRange;

  final TextEditingController availableSearchController = TextEditingController();
  final TextEditingController myOrdersSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  @override
  void dispose() {
    availableSearchController.dispose();
    myOrdersSearchController.dispose();
    super.dispose();
  }

  Future<String?> _token() async {
    final storage = TokenStorage();
    return await storage.getAccessToken();
  }

  Future<bool> _handleUnauthorized(http.Response response) async {
    if (response.statusCode != 401) return false;

    final storage = TokenStorage();
    await storage.deleteTokens();

    if (!mounted) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Session expired. Please login again.')),
    );
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
          (_) => false,
    );
    return true;
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadDashboard(),
      loadAvailableOrders(),
      loadMyOrders(),
    ]);
  }

  Future<void> loadDashboard() async {
    setState(() => dashboardLoading = true);
    try {
      final token = await _token();
      final response = await http.get(
        ApiConfig.uri('/api/delivery-staff/dashboard'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (await _handleUnauthorized(response)) return;
      if (response.statusCode == 200) {
        setState(() {
          dashboardData = Map<String, dynamic>.from(data);
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to load dashboard');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => dashboardLoading = false);
    }
  }

  Future<void> loadAvailableOrders() async {
    setState(() => availableLoading = true);
    try {
      final token = await _token();
      final response = await http.get(
        ApiConfig.uri('/api/delivery-staff/available-orders'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (await _handleUnauthorized(response)) return;
      if (response.statusCode == 200) {
        setState(() {
          availableOrders = List<dynamic>.from(data['orders'] ?? []);
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to load available orders');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => availableLoading = false);
    }
  }

  Future<void> loadMyOrders() async {
    setState(() => myOrdersLoading = true);
    try {
      final token = await _token();
      final queryParameters = <String, String>{'filter': myOrdersFilter};
      if (myOrdersCustomRange != null) {
        queryParameters['start_date'] = _formatDate(myOrdersCustomRange!.start);
        queryParameters['end_date'] = _formatDate(myOrdersCustomRange!.end);
      }

      final response = await http.get(
        ApiConfig.uri('/api/delivery-staff/my-orders', queryParameters: queryParameters),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (await _handleUnauthorized(response)) return;
      if (response.statusCode == 200) {
        setState(() {
          myOrders = List<dynamic>.from(data['orders'] ?? []);
          myOrdersSummary = Map<String, dynamic>.from(data['summary'] ?? {});
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to load my orders');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => myOrdersLoading = false);
    }
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> pickCustomRange() async {
    final now = DateTime.now();
    final initialRange = myOrdersCustomRange ?? DateTimeRange(
      start: now.subtract(const Duration(days: 6)),
      end: now,
    );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initialRange,
    );

    if (picked == null) return;
    setState(() => myOrdersCustomRange = picked);
    await loadMyOrders();
  }

  Future<void> clearCustomRange() async {
    setState(() => myOrdersCustomRange = null);
    await loadMyOrders();
  }

  Future<void> openOrderDetails(int orderId) async {
    setState(() {
      detailLoading = true;
      selectedOrder = null;
      showOrderDetails = true;
      selectedIndex = 2;
    });

    try {
      final token = await _token();
      final response = await http.get(
        ApiConfig.uri('/api/delivery-staff/order/$orderId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (await _handleUnauthorized(response)) return;
      if (response.statusCode == 200) {
        setState(() {
          selectedOrder = Map<String, dynamic>.from(data);
        });
      } else {
        throw Exception(data['message'] ?? 'Failed to load order details');
      }
    } catch (e) {
      showOrderDetails = false;
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => detailLoading = false);
    }
  }

  Future<void> acceptOrder(int orderId) async {
    try {
      final token = await _token();
      final response = await http.put(
        ApiConfig.uri('/api/delivery-staff/order/$orderId/accept'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};

      if (response.statusCode == 200) {
        _showMsg(data['message'] ?? 'Order accepted');
        await loadAll();
        if (mounted) {
          setState(() {
            selectedIndex = 2;
            showOrderDetails = true;
          });
        }
        await openOrderDetails(orderId);
      } else {
        throw Exception(data['message'] ?? 'Failed to accept order');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> pickedUpOrder(int orderId) async {
    try {
      final token = await _token();
      final response = await http.put(
        ApiConfig.uri('/api/delivery-staff/order/$orderId/picked-up'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        _showMsg(data['message'] ?? 'Order picked up');
        await loadAll();
        await openOrderDetails(orderId);
      } else {
        throw Exception(data['message'] ?? 'Failed to update order');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> outForDelivery(int orderId) async {
    try {
      final token = await _token();
      final response = await http.put(
        ApiConfig.uri('/api/delivery-staff/order/$orderId/out-for-delivery'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        _showMsg(data['message'] ?? 'Marked out for delivery');
        await loadAll();
        await openOrderDetails(orderId);
      } else {
        throw Exception(data['message'] ?? 'Failed to update order');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> deliveredOrder(int orderId) async {
    try {
      final token = await _token();
      final response = await http.put(
        ApiConfig.uri('/api/delivery-staff/order/$orderId/delivered'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        _showMsg(data['message'] ?? 'Order delivered');
        await loadAll();
        await openOrderDetails(orderId);
      } else {
        throw Exception(data['message'] ?? 'Failed to update order');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> updateCodPaymentStatus(int orderId, String paymentStatus) async {
    try {
      final token = await _token();
      final response = await http.put(
        ApiConfig.uri('/api/delivery-staff/order/$orderId/payment-status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'payment_status': paymentStatus}),
      );
      final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
      if (response.statusCode == 200) {
        _showMsg(data['message'] ?? 'Payment status updated');
        await loadAll();
        await openOrderDetails(orderId);
      } else {
        throw Exception(data['message'] ?? 'Failed to update payment status');
      }
    } catch (e) {
      _showMsg(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> changeMyOrdersFilter(String? v) async {
    setState(() {
      myOrdersFilter = v ?? 'active';
      showOrderDetails = false;
      selectedIndex = 2;
    });
    await loadMyOrders();
  }

  Future<void> openAvailableSection() async {
    setState(() {
      selectedIndex = 1;
      showOrderDetails = false;
      selectedOrder = null;
    });
    await loadAvailableOrders();
  }

  Future<void> openMyOrdersSection(String filter) async {
    setState(() {
      myOrdersFilter = filter;
      selectedIndex = 2;
      showOrderDetails = false;
      selectedOrder = null;
    });
    await loadMyOrders();
  }

  Future<void> openPaymentsPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeliveryStaffPaymentPage()),
    );
    await Future.wait([loadDashboard(), loadMyOrders()]);
  }

  Future<void> logout() async {
    final storage = TokenStorage();
    await storage.deleteTokens();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => LoginPage()),
          (_) => false,
    );
  }

  void _showMsg(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  List<dynamic> get filteredAvailableOrders {
    if (availableSearch.trim().isEmpty) return availableOrders;
    final q = availableSearch.toLowerCase().trim();
    return availableOrders.where((o) {
      return (o['order_id'] ?? '').toString().toLowerCase().contains(q) ||
          (o['user_name'] ?? '').toString().toLowerCase().contains(q) ||
          (o['seller_name'] ?? '').toString().toLowerCase().contains(q) ||
          (o['payment_method'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  List<dynamic> get filteredMyOrders {
    if (myOrdersSearch.trim().isEmpty) return myOrders;
    final q = myOrdersSearch.toLowerCase().trim();
    return myOrders.where((o) {
      return (o['order_id'] ?? '').toString().toLowerCase().contains(q) ||
          (o['user_name'] ?? '').toString().toLowerCase().contains(q) ||
          (o['seller_name'] ?? '').toString().toLowerCase().contains(q) ||
          (o['delivery_status'] ?? '').toString().toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (showOrderDetails) {
      body = DeliveryStaffOrderDetailsPage(
        isLoading: detailLoading,
        selectedOrder: selectedOrder,
        onBack: () {
          setState(() {
            showOrderDetails = false;
            selectedIndex = 2;
          });
        },
        onPickedUp: pickedUpOrder,
        onOutForDelivery: outForDelivery,
        onDelivered: deliveredOrder,
        onAccept: acceptOrder,
        onUpdatePaymentStatus: updateCodPaymentStatus,
      );
    } else if (selectedIndex == 0) {
      body = DeliveryStaffDashboardPage(
        isLoading: dashboardLoading,
        dashboardData: dashboardData,
        onOpenOrder: openOrderDetails,
        onOpenAvailable: openAvailableSection,
        onOpenMyOrders: (filter) => openMyOrdersSection(filter),
        onOpenPayments: openPaymentsPage,
      );
    } else if (selectedIndex == 1) {
      body = DeliveryStaffAvailableOrdersPage(
        isLoading: availableLoading,
        orders: filteredAvailableOrders,
        searchController: availableSearchController,
        onSearchChanged: (v) => setState(() => availableSearch = v),
        onClearSearch: () {
          availableSearchController.clear();
          setState(() => availableSearch = '');
        },
        onOpenOrder: openOrderDetails,
        onAcceptOrder: acceptOrder,
      );
    } else if (selectedIndex == 2) {
      body = DeliveryStaffMyOrdersPage(
        isLoading: myOrdersLoading,
        orders: filteredMyOrders,
        summary: myOrdersSummary,
        currentFilter: myOrdersFilter,
        customRange: myOrdersCustomRange,
        searchController: myOrdersSearchController,
        onSearchChanged: (v) => setState(() => myOrdersSearch = v),
        onClearSearch: () {
          myOrdersSearchController.clear();
          setState(() => myOrdersSearch = '');
        },
        onFilterChanged: changeMyOrdersFilter,
        onPickCustomRange: pickCustomRange,
        onClearCustomRange: clearCustomRange,
        onOpenOrder: openOrderDetails,
      );
    } else {
      body = DeliveryStaffProfilePage(
        dashboardData: dashboardData,
        onProfileUpdated: loadDashboard,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFFF7F7FB),
        foregroundColor: Colors.black,
        title: const Text('Delivery Staff Panel', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: loadAll, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: body,
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (index) {
            setState(() {
              selectedIndex = index;
              showOrderDetails = false;
              if (index != 2) {
                selectedOrder = null;
              }
            });
          },
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Colors.deepPurple,
          unselectedItemColor: Colors.black54,
          backgroundColor: Colors.white,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
            BottomNavigationBarItem(icon: Icon(Icons.assignment_rounded), label: 'Available'),
            BottomNavigationBarItem(icon: Icon(Icons.local_shipping_rounded), label: 'My Orders'),
            BottomNavigationBarItem(icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}