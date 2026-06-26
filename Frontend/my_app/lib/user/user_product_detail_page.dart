import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_auth_session.dart';
import 'package:my_app/user/user_order_summary_page.dart';
import 'package:my_app/user/user_wishlist_service.dart';

class ProductDetailPage extends StatefulWidget {
  final int prodId;
  final List wishlist;
  final Function onUpdate;
  final int? sellerId;
  final Map<String, dynamic>? initialProduct;

  const ProductDetailPage({
    super.key,
    required this.prodId,
    required this.wishlist,
    required this.onUpdate,
    this.sellerId,
    this.initialProduct,
  });

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int? currentUserId;
  Map<String, dynamic>? product;
  List<String> images = [];
  bool isWishlisted = false;
  int selectedQty = 1;
  bool isLoading = true;
  String? loadError;

  bool isSubmittingReview = false;
  bool canReview = false;
  double avgRating = 0;
  int reviewCount = 0;
  List<Map<String, dynamic>> reviews = [];
  Map<String, dynamic>? userReview;

  @override
  void initState() {
    super.initState();
    initData();
  }

  Future<void> initData() async {
    currentUserId = await UserAuthSession.getCurrentUserId();
    await fetchProduct();
    await fetchReviews();
  }

  String _normalizeImage(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.fileUrl(raw);
  }

  Map<String, dynamic>? _normalizedFallbackProduct() {
    final source = widget.initialProduct;
    if (source == null || source.isEmpty) return null;

    final fallback = Map<String, dynamic>.from(source);
    final normalizedProdId = int.tryParse((fallback['prod_id'] ?? widget.prodId).toString()) ?? widget.prodId;
    final normalizedSellerId = int.tryParse((fallback['seller_id'] ?? widget.sellerId ?? '').toString());

    fallback['prod_id'] = normalizedProdId;
    if (normalizedSellerId != null && normalizedSellerId > 0) {
      fallback['seller_id'] = normalizedSellerId;
    }

    fallback['prod_name'] = (fallback['prod_name'] ?? '').toString();
    fallback['prod_price'] = double.tryParse((fallback['prod_price'] ?? fallback['price'] ?? 0).toString()) ?? 0;
    fallback['brand'] = (fallback['brand'] ?? '').toString();
    fallback['description'] = (fallback['description'] ?? '').toString();
    fallback['seller_name'] = (fallback['seller_name'] ?? '').toString();
    fallback['stock_quantity'] = double.tryParse((fallback['stock_quantity'] ?? fallback['available_stock'] ?? 0).toString()) ?? 0;
    fallback['stock_status'] = (fallback['stock_status'] ?? 'Available').toString();

    if ((fallback['prod_image_url'] == null || fallback['prod_image_url'].toString().trim().isEmpty) &&
        fallback['prod_image'] != null) {
      fallback['prod_image_url'] = fallback['prod_image'];
    }
    return fallback;
  }

  List<String> _extractImages(Map<String, dynamic> data) {
    final dynamic rawImages = data['product_images'] ?? data['prod_images'];

    final list = rawImages is List && rawImages.isNotEmpty
        ? rawImages.map((e) => _normalizeImage(e)).where((e) => e.isNotEmpty).toList()
        : [
      _normalizeImage(data['prod_image_url'] ?? data['prod_image']),
      _normalizeImage(data['prod_image2']),
      _normalizeImage(data['prod_image3']),
    ].where((e) => e.isNotEmpty).toList();

    return list;
  }

  Future<void> _refreshWishlistState({dynamic sellerId}) async {
    try {
      final storedWishlist = await UserWishlistService.load(currentUserId)
          .timeout(const Duration(seconds: 4));

      widget.wishlist
        ..clear()
        ..addAll(storedWishlist);

      if (!mounted) return;
      setState(() {
        isWishlisted = UserWishlistService.contains(
          widget.wishlist,
          widget.prodId,
          sellerId: sellerId ?? widget.sellerId,
        );
      });
    } catch (_) {}
  }

  Future<void> _setFallbackProduct({String? errorMessage}) async {
    final fallback = _normalizedFallbackProduct();
    if (fallback == null || !mounted) {
      setState(() {
        product = null;
        images = [];
        isLoading = false;
        loadError = errorMessage ?? 'Product details could not be loaded right now.';
      });
      return;
    }

    setState(() {
      product = fallback;
      images = _extractImages(fallback);
      isWishlisted = UserWishlistService.contains(
        widget.wishlist,
        widget.prodId,
        sellerId: fallback['seller_id'] ?? widget.sellerId,
      );
      isLoading = false;
      loadError = null;
    });

    await _refreshWishlistState(sellerId: fallback['seller_id'] ?? widget.sellerId);
  }

  Future<void> fetchProduct() async {
    if (mounted) {
      setState(() {
        isLoading = true;
        loadError = null;
      });
    }

    try {
      final headers = await widget.getHeaders();
      http.Response? res;

      if (widget.sellerId != null && widget.sellerId! > 0) {
        try {
          res = await http
              .get(
            ApiConfig.uri(
              '/api/products/public/${widget.prodId}',
              queryParameters: {'seller_id': widget.sellerId.toString()},
            ),
            headers: headers,
          )
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          res = null;
        }
      }

      if (res == null || res.statusCode != 200) {
        try {
          res = await http
              .get(
            ApiConfig.uri('/api/products/public/${widget.prodId}'),
            headers: headers,
          )
              .timeout(const Duration(seconds: 12));
        } catch (_) {
          res = null;
        }
      }

      if (res == null || res.statusCode != 200) {
        await _setFallbackProduct(errorMessage: 'Product details could not be loaded right now.');
        return;
      }

      final decoded = jsonDecode(res.body);
      final Map<String, dynamic> data = decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(
        decoded['product'] is Map
            ? decoded['product']
            : decoded['data'] is Map
            ? decoded['data']
            : decoded,
      )
          : <String, dynamic>{};

      if (data.isEmpty || (int.tryParse((data['prod_id'] ?? 0).toString()) ?? 0) <= 0) {
        await _setFallbackProduct(errorMessage: 'Product details could not be loaded right now.');
        return;
      }

      final loadedImages = _extractImages(data);

      if (!mounted) return;
      setState(() {
        product = data;
        images = loadedImages;
        isWishlisted = UserWishlistService.contains(
          widget.wishlist,
          widget.prodId,
          sellerId: data['seller_id'] ?? widget.sellerId,
        );
        isLoading = false;
        loadError = null;
      });

      await _refreshWishlistState(sellerId: data['seller_id'] ?? widget.sellerId);
    } catch (_) {
      await _setFallbackProduct(errorMessage: 'Product details could not be loaded right now.');
    }
  }

  Future<void> fetchReviews() async {
    try {
      final sellerId = product?['seller_id'] ?? widget.sellerId;
      final res = await http.get(
        ApiConfig.uri(
          '/api/reviews/product/${widget.prodId}',
          queryParameters: sellerId == null ? null : {'seller_id': '$sellerId'},
        ),
        headers: await widget.getHeaders(),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return;

      final data = Map<String, dynamic>.from(jsonDecode(res.body));
      if (!mounted) return;
      setState(() {
        avgRating = double.tryParse((data['avg_rating'] ?? 0).toString()) ?? 0;
        reviewCount = int.tryParse((data['review_count'] ?? 0).toString()) ?? 0;
        canReview = data['can_review'] == true;
        userReview = data['user_review'] == null ? null : Map<String, dynamic>.from(data['user_review']);
        reviews = (data['reviews'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> addToCart() async {
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login again')),
      );
      return;
    }

    final res = await http.post(
      ApiConfig.uri('/add_to_cart'),
      headers: await widget.getHeaders(),
      body: jsonEncode({
        'user_id': currentUserId,
        'prod_id': widget.prodId,
        if (product!['seller_id'] != null) 'seller_id': product!['seller_id'],
        'quantity': selectedQty,
      }),
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to cart successfully')),
      );
      return;
    }

    String message = 'Unable to add to cart';
    try {
      final data = jsonDecode(res.body);
      message = (data['message'] ?? data['error'] ?? message).toString();
    } catch (_) {}
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void buyNowProduct() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderSummaryPage(
          singleItem: {
            'prod_id': product!['prod_id'],
            if (product!['seller_id'] != null) 'seller_id': product!['seller_id'],
            'prod_name': product!['prod_name'],
            'prod_price': product!['prod_price'],
            'prod_image': images.isNotEmpty ? images[0] : '',
            'seller_name': product!['seller_name'],
            'quantity': selectedQty,
            'stock_quantity': product!['stock_quantity'],
            'available_stock': product!['stock_quantity'],
            'stock_status': product!['stock_status'] ?? 'Available',
          },
        ),
      ),
    );
  }

  Future<void> toggleWishlist() async {
    if (product == null) return;

    final next = await UserWishlistService.toggle(
      userId: currentUserId,
      wishlist: widget.wishlist,
      product: {
        ...product!,
        'prod_image': images.isNotEmpty ? images.first : (product!['prod_image'] ?? ''),
        'prod_images': images,
      },
    );

    widget.wishlist
      ..clear()
      ..addAll(next);

    if (!mounted) return;
    setState(() {
      isWishlisted = UserWishlistService.contains(
        widget.wishlist,
        widget.prodId,
        sellerId: product?['seller_id'],
      );
    });
    widget.onUpdate();
  }

  Widget _buildImage(String imageUrl) {
    return Image.network(
      imageUrl,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return const Center(
          child: Icon(Icons.image_outlined, size: 80, color: Colors.grey),
        );
      },
    );
  }

  Widget _buildStarRow(double rating, {double size = 18}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = rating >= index + 1;
        final halfFilled = !filled && rating > index && rating < index + 1;
        return Icon(
          halfFilled ? Icons.star_half : (filled ? Icons.star : Icons.star_border),
          color: Colors.amber,
          size: size,
        );
      }),
    );
  }

  Future<void> _openReviewSheet() async {
    if (product == null) return;

    int localRating = int.tryParse((userReview?['rating'] ?? 0).toString()) ?? 0;
    final controller = TextEditingController(text: (userReview?['review'] ?? '').toString());
    final isEditing = userReview != null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 18,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit Your Review' : 'Rate This Product',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (product!['prod_name'] ?? '').toString(),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starNumber = index + 1;
                      return IconButton(
                        onPressed: () {
                          setModalState(() {
                            localRating = starNumber;
                          });
                        },
                        icon: Icon(
                          starNumber <= localRating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 34,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: InputDecoration(
                      hintText: 'Write your review here...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmittingReview
                          ? null
                          : () async {
                        if (localRating < 1 || localRating > 5) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please select a star rating')),
                          );
                          return;
                        }

                        Navigator.pop(context);
                        await _submitReview(localRating, controller.text.trim(), isEditing: isEditing);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(isEditing ? 'Update Review' : 'Submit Review'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _submitReview(int rating, String reviewText, {required bool isEditing}) async {
    if (product == null) return;

    setState(() {
      isSubmittingReview = true;
    });

    try {
      final requestFn = isEditing ? http.put : http.post;
      final res = await requestFn(
        ApiConfig.uri('/api/reviews'),
        headers: await widget.getHeaders(),
        body: jsonEncode({
          'prod_id': widget.prodId,
          'seller_id': product!['seller_id'],
          'rating': rating,
          'review': reviewText,
        }),
      );

      final data = jsonDecode(res.body);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((data['message'] ?? 'Review updated').toString())),
      );

      if (res.statusCode == 200) {
        await fetchProduct();
        await fetchReviews();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to submit review right now')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSubmittingReview = false;
        });
      }
    }
  }

  Widget _buildReviewSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
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
            'Ratings & Reviews',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                avgRating.toStringAsFixed(1),
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStarRow(avgRating, size: 20),
                  const SizedBox(height: 4),
                  Text(
                    reviewCount == 1 ? '1 review' : '$reviewCount reviews',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (canReview || userReview != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isSubmittingReview ? null : _openReviewSheet,
                icon: Icon(userReview != null ? Icons.edit_outlined : Icons.star_outline),
                label: Text(userReview != null ? 'Edit Your Review' : 'Write a Review'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            )
          else
            Text(
              'Review option will appear after your delivered purchase.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          if (userReview != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfff6f3fb),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Review',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  _buildStarRow(
                    double.tryParse((userReview!['rating'] ?? 0).toString()) ?? 0,
                    size: 18,
                  ),
                  if ((userReview!['review'] ?? '').toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text((userReview!['review'] ?? '').toString()),
                  ],
                ],
              ),
            ),
          ],
          if (reviews.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...reviews.take(5).map((review) {
              final name = (review['user_name'] ?? 'User').toString();
              final message = (review['review'] ?? '').toString();
              final rating = double.tryParse((review['rating'] ?? 0).toString()) ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        _buildStarRow(rating, size: 16),
                      ],
                    ),
                    if (message.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        style: TextStyle(color: Colors.grey.shade800),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (product == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              loadError ?? 'Product details could not be loaded right now.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final int availableStock = int.tryParse((product!['stock_quantity'] ?? product!['quantity'] ?? 0).toString()) ?? 0;
    final bool isOutOfStock = availableStock <= 0;
    if (!isOutOfStock && selectedQty > availableStock) {
      selectedQty = availableStock;
    }
    final double price = double.tryParse(product!['prod_price'].toString()) ?? 0;
    double unit = double.tryParse((product!['unit_type'] ?? 1).toString()) ?? 1;
    if (unit <= 0) unit = 1;
    final double unitPrice = price / unit;
    final double totalPrice = unitPrice * selectedQty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  height: 300,
                  width: double.infinity,
                  child: images.isEmpty
                      ? const Center(child: Icon(Icons.image_outlined, size: 80, color: Colors.grey))
                      : PageView.builder(
                    itemCount: images.length,
                    itemBuilder: (context, index) => _buildImage(images[index]),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: toggleWishlist,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.grey.shade300, blurRadius: 5),
                        ],
                      ),
                      child: Icon(
                        isWishlisted ? Icons.favorite : Icons.favorite_border,
                        color: isWishlisted ? Colors.red : Colors.black,
                      ),
                    ),
                  ),
                )
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (product!['prod_name'] ?? '').toString(),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _buildStarRow(avgRating, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '${avgRating.toStringAsFixed(1)} ($reviewCount)',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹ ${totalPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Seller: ${(product!['seller_name'] ?? '').toString()}'),
                  const SizedBox(height: 6),
                  Text('Brand: ${(product!['brand'] ?? '').toString()}'),
                  const SizedBox(height: 6),
                  Text('Description: ${(product!['description'] ?? '').toString()}'),
                  const SizedBox(height: 6),
                  Text(
                    isOutOfStock ? 'Out of Stock' : 'Available Stock: $availableStock',
                    style: TextStyle(
                      color: isOutOfStock ? Colors.red : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade800, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No Return Policy: Once this product is delivered, it cannot be returned.',
                            style: TextStyle(
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text('Quantity:', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                              onTap: isOutOfStock || selectedQty <= 1
                                  ? null
                                  : () {
                                setState(() {
                                  selectedQty--;
                                });
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.remove,
                                  color: isOutOfStock || selectedQty <= 1 ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ),
                            Container(
                              width: 52,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(color: Colors.grey.shade300),
                                  right: BorderSide(color: Colors.grey.shade300),
                                ),
                              ),
                              child: Text(
                                selectedQty.toString(),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                              ),
                            ),
                            InkWell(
                              borderRadius: const BorderRadius.horizontal(right: Radius.circular(14)),
                              onTap: isOutOfStock || selectedQty >= availableStock
                                  ? null
                                  : () {
                                setState(() {
                                  selectedQty++;
                                });
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.add,
                                  color: isOutOfStock || selectedQty >= availableStock ? Colors.grey : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: isOutOfStock ? null : addToCart,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(isOutOfStock ? 'Out of Stock' : 'Add to Cart'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: isOutOfStock ? null : buyNowProduct,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(isOutOfStock ? 'Out of Stock' : 'Buy Now'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildReviewSummaryCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}