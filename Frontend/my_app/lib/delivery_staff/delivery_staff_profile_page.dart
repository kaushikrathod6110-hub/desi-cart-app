import 'package:flutter/material.dart';
import 'delivery_staff_edit_profile_page.dart';
import 'delivery_staff_widgets.dart';
import 'delivery_staff_rating_page.dart';

class DeliveryStaffProfilePage extends StatelessWidget {
  final Map<String, dynamic>? dashboardData;
  final Future<void> Function() onProfileUpdated;

  const DeliveryStaffProfilePage({
    super.key,
    required this.dashboardData,
    required this.onProfileUpdated,
  });

  @override
  Widget build(BuildContext context) {
    final profile = Map<String, dynamic>.from((dashboardData ?? {})['profile'] ?? {});

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              deliverySoftCard(
                child: Column(
                  children: [
                    deliveryProfileAvatar(
                      profile: profile,
                      radius: 34,
                      fallbackIcon: Icons.delivery_dining,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${profile['delivery_staff_name'] ?? '-'}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${profile['d_s_email'] ?? '-'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 10),
                    deliveryStatusChip('${profile['d_s_status'] ?? '-'}'),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const DeliveryStaffRatingPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.star),
                          label: const Text('My Ratings'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DeliveryStaffEditProfilePage(
                                  initialProfile: profile,
                                  onProfileUpdated: onProfileUpdated,
                                ),
                              ),
                            );
                            await onProfileUpdated();
                          },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit Profile'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              deliverySoftCard(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.phone),
                      title: const Text('Mobile'),
                      subtitle: Text('${profile['d_s_mobile'] ?? '-'}'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.home),
                      title: const Text('Address'),
                      subtitle: Text('${profile['d_s_address'] ?? '-'}'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.pin_drop),
                      title: const Text('Pincode'),
                      subtitle: Text('${profile['d_s_pincode'] ?? '-'}'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.two_wheeler),
                      title: const Text('Vehicle Type'),
                      subtitle: Text('${profile['vehicle_type'] ?? '-'}'),
                    ),
                    if (((profile['vehicle_type'] ?? '').toString() != 'Cycle') &&
                        ((profile['vehicle_type'] ?? '').toString() != 'None')) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.badge),
                        title: const Text('Licence No'),
                        subtitle: Text(
                          '${(profile['staff_licence_no'] ?? '').toString().trim().isEmpty ? '-' : profile['staff_licence_no']}',
                        ),
                      ),
                    ],
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.credit_card),
                      title: const Text('Aadhar No'),
                      subtitle: Text('${profile['aadhar_card_no'] ?? '-'}'),
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