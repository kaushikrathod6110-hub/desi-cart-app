import 'package:flutter/material.dart';
import 'delivery_staff_widgets.dart';

class DeliveryStaffOrderDetailsPage extends StatelessWidget {
  final bool isLoading;
  final Map<String, dynamic>? selectedOrder;
  final VoidCallback onBack;
  final Future<void> Function(int orderId) onPickedUp;
  final Future<void> Function(int orderId) onOutForDelivery;
  final Future<void> Function(int orderId) onDelivered;
  final Future<void> Function(int orderId) onAccept;
  final Future<void> Function(int orderId, String paymentStatus) onUpdatePaymentStatus;

  const DeliveryStaffOrderDetailsPage({
    super.key,
    required this.isLoading,
    required this.selectedOrder,
    required this.onBack,
    required this.onPickedUp,
    required this.onOutForDelivery,
    required this.onDelivered,
    required this.onAccept,
    required this.onUpdatePaymentStatus,
  });

  Widget _actionButtonsForOrder(Map<String, dynamic> o) {
    final status = effectiveDeliveryStatus(o);

    if (status == 'Assigned') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        onPressed: () => onPickedUp(o['order_id']),
        icon: const Icon(Icons.inventory_2_outlined),
        label: const Text('Mark Picked Up'),
      );
    }

    if (status == 'Picked Up') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        onPressed: () => onOutForDelivery(o['order_id']),
        icon: const Icon(Icons.local_shipping),
        label: const Text('Out For Delivery'),
      );
    }

    if (status == 'Out For Delivery') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        onPressed: () => onDelivered(o['order_id']),
        icon: const Icon(Icons.done_all),
        label: const Text('Mark Delivered'),
      );
    }

    if (status == 'Delivered') return deliveryStatusChip('Delivered');

    if (status == 'Unassigned') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        onPressed: () => onAccept(o['order_id']),
        icon: const Icon(Icons.assignment_turned_in),
        label: const Text('Accept Order'),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _paymentSection(Map<String, dynamic> o) {
    final paymentMethod = (o['payment_method'] ?? '').toString().toUpperCase();
    final paymentStatus = (o['payment_status'] ?? '').toString();
    final deliveryStatus = effectiveDeliveryStatus(o);
    final paymentLocked = deliveryStatus == 'Delivered' && paymentStatus == 'Paid';

    if (paymentMethod != 'COD') return const SizedBox.shrink();

    return deliverySoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COD Payment Update', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            deliveryStatus == 'Delivered'
                ? 'Delivery staff can update COD payment after delivery.'
                : 'COD payment buttons will appear after order is delivered.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              deliveryStatusChip('Current: ${paymentStatus.isEmpty ? '-' : paymentStatus}'),
              if (deliveryStatus == 'Delivered')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: paymentLocked || paymentStatus == 'Paid' ? null : () => onUpdatePaymentStatus(o['order_id'], 'Paid'),
                  icon: const Icon(Icons.payments),
                  label: const Text('Cash Received'),
                ),
              if (deliveryStatus == 'Delivered')
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: paymentLocked || paymentStatus == 'Failed' ? null : () => onUpdatePaymentStatus(o['order_id'], 'Failed'),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Mark Failed'),
                ),
              if (deliveryStatus == 'Delivered')
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: paymentLocked || paymentStatus == 'Pending' ? null : () => onUpdatePaymentStatus(o['order_id'], 'Pending'),
                  icon: const Icon(Icons.hourglass_empty),
                  label: const Text('Mark Pending'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    final o = selectedOrder;
    if (o == null) return const Center(child: Text('No order selected'));

    final earningAmount = double.tryParse((o['earning_amount'] ?? 0).toString()) ?? 0;
    final paymentAmount = double.tryParse((o['payment_amount'] ?? o['total_amount'] ?? 0).toString()) ?? 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  Text('Order #${o['order_id']}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 16),
              deliverySoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Order Overview', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        deliveryDashboardCard(
                          title: 'Amount',
                          value: 'Rs. ${formatMoney(o['total_amount'])}',
                          icon: Icons.currency_rupee,
                          color: Colors.green,
                        ),
                        deliveryDashboardCard(
                          title: 'Earning',
                          value: 'Rs. ${formatMoney(earningAmount)}',
                          icon: Icons.account_balance_wallet,
                          color: Colors.teal,
                        ),
                        deliveryDashboardCard(
                          title: 'Payment',
                          value: '${o['payment_status']}',
                          icon: Icons.payments,
                          color: Colors.orange,
                        ),
                        deliveryDashboardCard(
                          title: 'Delivery',
                          value: effectiveDeliveryStatus(o),
                          icon: Icons.local_shipping,
                          color: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerRight, child: _actionButtonsForOrder(o)),
              const SizedBox(height: 16),
              _paymentSection(o),
              const SizedBox(height: 16),
              deliverySoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Payment Details', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    deliveryTimelineTile(
                      title: 'Payment Method',
                      value: '${o['payment_method'] ?? '-'}',
                      icon: Icons.credit_card,
                      color: Colors.indigo,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Payment Status',
                      value: '${o['payment_status'] ?? '-'}',
                      icon: Icons.payments_outlined,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Transaction ID',
                      value: ((o['transaction_id'] ?? '').toString().trim().isEmpty) ? '-' : (o['transaction_id']).toString(),
                      icon: Icons.receipt_long,
                      color: Colors.teal,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Payment Amount',
                      value: '₹ ${formatMoney(paymentAmount)}',
                      icon: Icons.currency_rupee,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Payment Date',
                      value: formatDateTimeValue(o['payment_date']),
                      icon: Icons.calendar_today,
                      color: Colors.blue,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              deliverySoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Customer & Delivery Details', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    deliveryTimelineTile(
                      title: 'Customer Name',
                      value: '${o['user_name'] ?? '-'}',
                      icon: Icons.person,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Seller Name',
                      value: '${o['seller_name'] ?? '-'}',
                      icon: Icons.store,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Order Date',
                      value: formatDateTimeValue(o['order_date']),
                      icon: Icons.calendar_today,
                      color: Colors.green,
                    ),
                    const SizedBox(height: 12),
                    deliveryTimelineTile(
                      title: 'Address',
                      value: ((o['delivery_address'] ?? o['user_address'] ?? '').toString().trim().isEmpty)
                          ? '-'
                          : (o['delivery_address'] ?? o['user_address']).toString(),
                      icon: Icons.location_on,
                      color: Colors.red,
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
}