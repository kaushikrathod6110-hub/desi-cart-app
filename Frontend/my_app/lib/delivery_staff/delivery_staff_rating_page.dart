import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';

class DeliveryStaffRatingPage extends StatefulWidget {
  final int? orderId;
  final int? deliveryStaffId;
  final String deliveryStaffName;
  final String? vehicleType;

  const DeliveryStaffRatingPage({
    super.key,
    this.orderId,
    this.deliveryStaffId,
    this.deliveryStaffName = '',
    this.vehicleType,
  });

  bool get isUserMode => orderId != null && deliveryStaffId != null;

  @override
  State<DeliveryStaffRatingPage> createState() => _DeliveryStaffRatingPageState();
}

class _DeliveryStaffRatingPageState extends State<DeliveryStaffRatingPage> {
  static const List<String> availableTags = [
    'On time',
    'Polite',
    'Fast delivery',
    'Safe delivery',
    'Good behavior',
    'Package handled well',
  ];

  bool isLoading = true;
  bool isSaving = false;
  bool isSkipped = false;
  bool hasReview = false;
  int selectedRating = 0;
  final TextEditingController reviewController = TextEditingController();
  final Set<String> selectedTags = <String>{};

  List<Map<String, dynamic>> ratings = <Map<String, dynamic>>[];
  double averageRating = 0;

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  void initState() {
    super.initState();
    if (widget.isUserMode) {
      fetchExistingReview();
    } else {
      fetchMyRatings();
    }
  }

  @override
  void dispose() {
    reviewController.dispose();
    super.dispose();
  }

  Future<void> fetchExistingReview() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        ApiConfig.uri('/api/delivery-staff/reviews/order/${widget.orderId}'),
        headers: await getHeaders(),
      );

      if (res.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body));
        final review = data['review'] is Map ? Map<String, dynamic>.from(data['review']) : null;
        final tags = (review?['review_tags'] as List? ?? []).map((e) => e.toString()).toList();
        if (!mounted) return;
        setState(() {
          isSkipped = data['is_skipped'] == true;
          hasReview = data['has_review'] == true;
          selectedRating = int.tryParse((review?['rating'] ?? 0).toString()) ?? 0;
          reviewController.text = (review?['review'] ?? '').toString();
          selectedTags
            ..clear()
            ..addAll(tags);
          isLoading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchMyRatings() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        ApiConfig.uri('/api/delivery-staff/my-ratings'),
        headers: await getHeaders(),
      );
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        final rawRatings = (data['ratings'] as List? ?? []);
        ratings = rawRatings.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        averageRating = double.tryParse((data['average_rating'] ?? 0).toString()) ?? 0;
        isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        ratings = <Map<String, dynamic>>[];
        averageRating = 0;
        isLoading = false;
      });
    }
  }

  Future<void> saveReview() async {
    if (selectedRating < 1 || selectedRating > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a star rating')),
      );
      return;
    }

    setState(() => isSaving = true);
    try {
      final res = await http.post(
        ApiConfig.uri('/api/delivery-staff/reviews/order/${widget.orderId}'),
        headers: await getHeaders(),
        body: jsonEncode({
          'action': 'review',
          'rating': selectedRating,
          'review': reviewController.text.trim(),
          'review_tags': selectedTags.toList(),
        }),
      );

      final data = jsonDecode(res.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((data['message'] ?? 'Delivery review saved').toString())),
      );
      if (res.statusCode == 200) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save delivery review right now')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Future<void> skipReview() async {
    setState(() => isSaving = true);
    try {
      final res = await http.post(
        ApiConfig.uri('/api/delivery-staff/reviews/order/${widget.orderId}'),
        headers: await getHeaders(),
        body: jsonEncode({'action': 'skip'}),
      );

      final data = jsonDecode(res.body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((data['message'] ?? 'Skipped').toString())),
      );
      if (res.statusCode == 200) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to skip right now')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  Widget buildStarSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final star = index + 1;
        return IconButton(
          onPressed: isSaving
              ? null
              : () {
            setState(() {
              selectedRating = star;
            });
          },
          icon: Icon(
            star <= selectedRating ? Icons.star : Icons.star_border,
            color: Colors.amber,
            size: 34,
          ),
        );
      }),
    );
  }

  Widget buildTagChip(String tag) {
    final selected = selectedTags.contains(tag);
    return FilterChip(
      label: Text(tag),
      selected: selected,
      onSelected: isSaving
          ? null
          : (value) {
        setState(() {
          if (value) {
            selectedTags.add(tag);
          } else {
            selectedTags.remove(tag);
          }
        });
      },
    );
  }

  Widget buildRatingStars(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
            (index) => Icon(
          index < rating ? Icons.star : Icons.star_border,
          color: Colors.amber,
          size: 18,
        ),
      ),
    );
  }

  Widget buildStaffRatingsView() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (ratings.isEmpty) {
      return const Center(child: Text('No ratings yet'));
    }

    return RefreshIndicator(
      onRefresh: fetchMyRatings,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My Ratings',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Average Rating: ${averageRating.toStringAsFixed(1)} ★',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ratings.length} review(s)',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ...ratings.map((item) {
            final reviewerName = (item['user_name'] ?? '').toString().trim();
            final review = (item['review'] ?? item['comment'] ?? '').toString();
            final createdAt = (item['created_at'] ?? '').toString();
            final tagList = (item['review_tags'] as List? ?? []).map((e) => e.toString()).toList();
            final ratingValue = int.tryParse((item['rating'] ?? 0).toString()) ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      buildRatingStars(ratingValue),
                      if (createdAt.isNotEmpty)
                        Flexible(
                          child: Text(
                            createdAt,
                            textAlign: TextAlign.end,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  if (reviewerName.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      reviewerName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (tagList.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: tagList
                          .map((tag) => Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ))
                          .toList(),
                    ),
                  ],
                  if (review.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(review),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget buildUserReviewView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.deliveryStaffName.isEmpty ? 'Delivery Partner' : widget.deliveryStaffName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if ((widget.vehicleType ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Vehicle: ${widget.vehicleType}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  hasReview ? 'Edit your delivery feedback' : 'Share your delivery experience',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How was the delivery?',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                buildStarSelector(),
                const SizedBox(height: 12),
                const Text(
                  'Quick feedback',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableTags.map(buildTagChip).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reviewController,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: InputDecoration(
                    hintText: 'Write about the delivery experience...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSaving ? null : skipReview,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isSaving ? null : saveReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(isSaving ? 'Saving...' : (hasReview ? 'Update Rating' : 'Submit Rating')),
                ),
              ),
            ],
          ),
          if (isSkipped) ...[
            const SizedBox(height: 14),
            Text(
              'You had skipped this delivery rating earlier. You can still submit it now if you want.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f3fb),
      appBar: AppBar(
        title: Text(widget.isUserMode ? 'Rate Delivery' : 'My Ratings'),
        backgroundColor: Colors.blue,
      ),
      body: widget.isUserMode
          ? (isLoading ? const Center(child: CircularProgressIndicator()) : buildUserReviewView())
          : buildStaffRatingsView(),
    );
  }
}