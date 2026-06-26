import 'package:flutter/material.dart';
import 'delivery_staff_widgets.dart';

class DeliveryStaffDashboardPage extends StatelessWidget {
  final bool isLoading;
  final Map<String, dynamic>? dashboardData;
  final Future<void> Function(int orderId) onOpenOrder;
  final VoidCallback onOpenAvailable;
  final ValueChanged<String> onOpenMyOrders;
  final VoidCallback onOpenPayments;

  const DeliveryStaffDashboardPage({
    super.key,
    required this.isLoading,
    required this.dashboardData,
    required this.onOpenOrder,
    required this.onOpenAvailable,
    required this.onOpenMyOrders,
    required this.onOpenPayments,
  });

  Widget _metricCard({
    required BuildContext context,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 126,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [color.withOpacity(0.14), color.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: color.withOpacity(0.20)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withOpacity(0.14),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
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

  Widget _paymentCard({
    required String todayEarning,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              colors: [Colors.teal.withOpacity(0.14), Colors.teal.withOpacity(0.05)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.teal.withOpacity(0.20)),
            boxShadow: [
              BoxShadow(
                color: Colors.teal.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.teal.withOpacity(0.14),
                child: const Icon(Icons.account_balance_wallet, color: Colors.teal, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Details',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Open full payment summary and delivered payment records',
                      style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Today Earning',
                    style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹$todayEarning',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = dashboardData ?? {};
    final profile = Map<String, dynamic>.from(data['profile'] ?? {});
    final summary = Map<String, dynamic>.from(data['summary'] ?? {});
    final earnings = Map<String, dynamic>.from(data['earnings'] ?? {});
    final todayEarnings = Map<String, dynamic>.from(earnings['today'] ?? {});
    final recentOrders = List<dynamic>.from(data['recent_orders'] ?? []);

    final Map<String, Map<String, dynamic>> groupedOrders = {};
    for (final raw in recentOrders) {
      final item = Map<String, dynamic>.from(raw);
      final key = item['order_id'].toString();
      if (!groupedOrders.containsKey(key)) {
        groupedOrders[key] = {...item, 'sellers': [item]};
      } else {
        (groupedOrders[key]!['sellers'] as List).add(item);
      }
    }
    final orderList = groupedOrders.values.toList();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              deliverySoftCard(
                child: Row(
                  children: [
                    deliveryProfileAvatar(
                      profile: profile,
                      radius: 30,
                      fallbackIcon: Icons.delivery_dining,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${profile['delivery_staff_name'] ?? '-'}',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${profile['d_s_email'] ?? '-'}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    deliveryStatusChip('${profile['d_s_status'] ?? '-'}'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              deliverySectionTitle(
                'Dashboard Overview',
                subtitle: 'Tap any card to open the related section',
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final double cardWidth = constraints.maxWidth < 700
                      ? (constraints.maxWidth - 12) / 2
                      : (constraints.maxWidth - 36) / 3;
                  return Column(
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: cardWidth,
                            child: _metricCard(
                              context: context,
                              title: 'Available Orders',
                              value: '${summary['available_orders'] ?? 0}',
                              icon: Icons.assignment,
                              color: Colors.orange,
                              onTap: onOpenAvailable,
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _metricCard(
                              context: context,
                              title: 'Active Orders',
                              value: '${summary['active_orders'] ?? 0}',
                              icon: Icons.local_shipping,
                              color: Colors.deepPurple,
                              onTap: () => onOpenMyOrders('active'),
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _metricCard(
                              context: context,
                              title: 'Delivered Orders',
                              value: '${summary['delivered_orders'] ?? 0}',
                              icon: Icons.done_all,
                              color: Colors.green,
                              onTap: () => onOpenMyOrders('delivered'),
                            ),
                          ),
                          SizedBox(
                            width: cardWidth,
                            child: _metricCard(
                              context: context,
                              title: 'Total Assigned',
                              value: '${summary['total_assigned'] ?? 0}',
                              icon: Icons.list_alt,
                              color: Colors.blue,
                              onTap: () => onOpenMyOrders('all'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _paymentCard(
                        todayEarning: formatMoney(todayEarnings['total_earning'] ?? 0),
                        onTap: onOpenPayments,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              deliverySectionTitle(
                'Recent Active Orders',
                subtitle: 'Your latest delivery activity',
              ),
              const SizedBox(height: 12),
              if (orderList.isEmpty)
                deliverySoftCard(
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Center(child: Text('No recent orders available')),
                  ),
                )
              else
                ...orderList.map((item) {
                  return deliveryOrderListCard(
                    item,
                    showAccept: false,
                    showOpen: true,
                    onView: () => onOpenOrder(item['order_id']),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }
}