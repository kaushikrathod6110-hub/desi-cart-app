import 'package:flutter/material.dart';
import 'delivery_staff_widgets.dart';

class DeliveryStaffMyOrdersPage extends StatelessWidget {
  final bool isLoading;
  final List<dynamic> orders;
  final Map<String, dynamic> summary;
  final String currentFilter;
  final DateTimeRange? customRange;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String?> onFilterChanged;
  final VoidCallback onPickCustomRange;
  final VoidCallback onClearCustomRange;
  final Future<void> Function(int orderId) onOpenOrder;

  const DeliveryStaffMyOrdersPage({
    super.key,
    required this.isLoading,
    required this.orders,
    required this.summary,
    required this.currentFilter,
    required this.customRange,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onFilterChanged,
    required this.onPickCustomRange,
    required this.onClearCustomRange,
    required this.onOpenOrder,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final Map<String, Map<String, dynamic>> groupedOrders = {};
    for (var o in orders) {
      final item = Map<String, dynamic>.from(o);
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
            children: [
              deliverySectionTitle(
                'My Orders',
                subtitle: 'Manage and track your assigned deliveries',
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final filterWidget = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withOpacity(0.08)),
                    ),
                    child: DropdownButton<String>(
                      value: currentFilter,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(value: 'delivered', child: Text('Delivered')),
                      ],
                      onChanged: onFilterChanged,
                    ),
                  );

                  final searchWidget = deliverySearchField(
                    hint: 'Search my orders',
                    controller: searchController,
                    onChanged: onSearchChanged,
                    onClear: onClearSearch,
                  );

                  if (constraints.maxWidth >= 560) {
                    return Row(
                      children: [
                        Expanded(child: searchWidget),
                        const SizedBox(width: 10),
                        filterWidget,
                      ],
                    );
                  }

                  return Column(
                    children: [
                      searchWidget,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: filterWidget),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              if (orderList.isEmpty)
                deliverySoftCard(
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No orders found'),
                    ),
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