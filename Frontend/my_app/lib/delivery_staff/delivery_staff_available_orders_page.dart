import 'package:flutter/material.dart';
import 'delivery_staff_widgets.dart';

class DeliveryStaffAvailableOrdersPage extends StatelessWidget {
  final bool isLoading;
  final List<dynamic> orders;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final Future<void> Function(int orderId) onOpenOrder;
  final Future<void> Function(int orderId) onAcceptOrder;

  const DeliveryStaffAvailableOrdersPage({
    super.key,
    required this.isLoading,
    required this.orders,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onOpenOrder,
    required this.onAcceptOrder,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 🔥 GROUPING LOGIC (ONLY CHANGE)
  // 🔥 GROUP BY USER + TIME
final Map<String, Map<String, dynamic>> groupedOrders = {};

for (var o in orders) {
  final item = Map<String, dynamic>.from(o);

  final key = item['order_id'].toString();

  if (!groupedOrders.containsKey(key)) {
    groupedOrders[key] = {
      ...item,
      "sellers": [item],
    };
  } else {
    groupedOrders[key]!["sellers"].add(item);
  }
}

final orderList = groupedOrders.values.toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              deliverySectionTitle(
                'Available Orders',
                subtitle: 'Accept new orders for delivery',
              ),
              const SizedBox(height: 14),

              deliverySearchField(
                hint: 'Search available order',
                controller: searchController,
                onChanged: onSearchChanged,
                onClear: onClearSearch,
              ),

              const SizedBox(height: 16),

              if (orderList.isEmpty)
                deliverySoftCard(
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No available orders'),
                    ),
                  ),
                )
              else
                ...orderList.map((item){
                  return deliveryOrderListCard(
                  item,
                  showAccept: true,
                  showOpen: true,
                  onView: () => onOpenOrder(item['order_id']),
                  onAccept: () => onAcceptOrder(item['order_id']),
                );
                }),
            ],
          ),
        ),
      ),
    );
  }
}