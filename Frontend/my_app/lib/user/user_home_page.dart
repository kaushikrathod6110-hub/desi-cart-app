
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_auth_session.dart';
import 'package:my_app/user/user_notification_page.dart';
import 'package:my_app/user/user_product_detail_page.dart';
import 'package:my_app/user/user_profile_page.dart';
import 'package:my_app/user/user_seller_detail_page.dart';
import 'package:my_app/user/user_seller_page.dart';
import 'package:my_app/user/user_wishlist_page.dart';
import 'package:my_app/user/user_wishlist_service.dart';

import 'user_cart_page.dart';
import 'user_category_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int? currentUserId;
  int currentIndex = 0;
  String searchQuery = '';
  final TextEditingController searchController = TextEditingController();

  String selectedAvailability = 'all';
  String selectedPriceRange = 'all';
  String selectedSort = 'default';
  int? selectedSellerId;
  String selectedCategoryName = 'all';
  bool selectedNearbyOnly = false;

  List sellers = [];
  List products = [];
  List nearbyProducts = [];
  List otherProducts = [];
  List<dynamic> wishlist = [];

  bool isLoading = true;
  String profileImageUrl = '';
  bool notificationsEnabled = true;
  int notificationCount = 0;

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
    searchController.addListener(() {
      final value = searchController.text;
      if (searchQuery != value) {
        if (mounted) {
          setState(() {
            searchQuery = value;
          });
        } else {
          searchQuery = value;
        }
        fetchHomeData();
      }
    });
    initData();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> initData() async {
    currentUserId = await UserAuthSession.getCurrentUserId();
    wishlist = await UserWishlistService.load(currentUserId);
    await fetchProfileImage();
    await loadNotificationPreference();
    await fetchHomeData();
    await fetchNotificationCount();
    if (mounted) setState(() {});
  }

  Future<void> refreshWishlist() async {
    wishlist = await UserWishlistService.load(currentUserId);
    if (mounted) setState(() {});
  }

  Future<void> fetchProfileImage() async {
    if (currentUserId == null) return;

    try {
      final res = await http.get(
        ApiConfig.uri('/get_user/$currentUserId'),
        headers: await getHeaders(),
      );

      if (res.statusCode == 200) {
        final data = Map<String, dynamic>.from(jsonDecode(res.body));
        final raw = (data['profile_image_url'] ?? data['profile_image'] ?? '')
            .toString()
            .trim();

        if (!mounted) return;
        setState(() {
          profileImageUrl = raw.isEmpty
              ? ''
              : (raw.startsWith('http://') || raw.startsWith('https://')
              ? raw
              : ApiConfig.fileUrl(raw));
        });
      }
    } catch (_) {}
  }

  Future<void> loadNotificationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    notificationsEnabled = prefs.getBool('notifications') ?? true;
  }

  Future<void> fetchNotificationCount() async {
    if (!notificationsEnabled) {
      if (mounted) {
        setState(() {
          notificationCount = 0;
        });
      }
      return;
    }

    try {
      final response = await http.get(
        ApiConfig.uri('/api/user/notifications'),
        headers: await getHeaders(),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            notificationCount = data is List ? data.length : 0;
          });
        }
      }
    } catch (_) {}
  }

  bool get _isNearbySearch => _shouldUseNearbyFilter;

  Future<void> fetchHomeData() async {
    final isNearbySearch = _isNearbySearch;
    final sellerParams = <String, String>{};
    final productParams = <String, String>{};

    if (searchQuery.trim().isNotEmpty) {
      sellerParams['search'] = searchQuery.trim();
      productParams['search'] = searchQuery.trim();
    }

    if (isNearbySearch && currentUserId != null) {
      sellerParams['nearby_user_id'] = currentUserId.toString();
      sellerParams['nearby_only'] = '1';
      productParams['nearby_user_id'] = currentUserId.toString();
      productParams['nearby_only'] = '1';
    }

    final sellerRes = await http.get(
      ApiConfig.uri('/api/sellers/public', queryParameters: sellerParams.isEmpty ? null : sellerParams),
      headers: await getHeaders(),
    );
    final productRes = await http.get(
      ApiConfig.uri('/api/products/public', queryParameters: productParams.isEmpty ? null : productParams),
      headers: await getHeaders(),
    );

    if (sellerRes.statusCode == 200 && productRes.statusCode == 200) {
      sellers = jsonDecode(sellerRes.body);
      products = jsonDecode(productRes.body);
      if (isNearbySearch) {
        nearbyProducts = products.where((item) => item is Map && item['is_nearby'] == true).toList();
        otherProducts = products.where((item) => item is Map && item['is_nearby'] != true).toList();
      } else {
        nearbyProducts = [];
        otherProducts = [];
      }
    } else {
      sellers = [];
      products = [];
      nearbyProducts = [];
      otherProducts = [];
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> addToCart(int prodId, {int? sellerId}) async {
    if (currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login again')),
      );
      return;
    }

    final response = await http.post(
      ApiConfig.uri('/add_to_cart'),
      headers: await getHeaders(),
      body: jsonEncode({
        'user_id': currentUserId,
        'prod_id': prodId,
        if (sellerId != null) 'seller_id': sellerId,
        'quantity': 1,
      }),
    );

    if (response.statusCode == 200 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to cart successfully')),
      );
    }
  }

  String _normalizeImage(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    return ApiConfig.fileUrl(raw);
  }

  String _sellerLogoUrl(Map seller) {
    return _normalizeImage(seller['store_logo_url'] ?? seller['store_logo']);
  }

  String _productImageUrl(Map product) {
    final dynamic imageList = product['product_images'] ?? product['prod_images'];
    if (imageList is List && imageList.isNotEmpty) {
      return _normalizeImage(imageList.first);
    }
    return _normalizeImage(product['prod_image_url'] ?? product['prod_image'] ?? product['image']);
  }

  Widget _buildSellerAvatar(Map seller, {double size = 60}) {
    final imageUrl = _sellerLogoUrl(seller);
    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.blue.shade100,
        child: Icon(Icons.store, color: Colors.blue, size: size * 0.5),
      );
    }

    return ClipOval(
      child: Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return CircleAvatar(
            radius: size / 2,
            backgroundColor: Colors.blue.shade100,
            child: Icon(Icons.store, color: Colors.blue, size: size * 0.5),
          );
        },
      ),
    );
  }

  bool _isOutOfStock(Map product) {
    final status = (product['stock_status'] ?? '').toString().toLowerCase();
    final qty = int.tryParse((product['stock_quantity'] ?? '0').toString()) ?? 0;
    return status == 'out of stock' || qty <= 0;
  }

  double _productPrice(Map product) {
    return double.tryParse((product['prod_price'] ?? 0).toString()) ?? 0;
  }

  String _normalizedText(dynamic value) {
    return value
        .toString()
        .toLowerCase()
        .replaceAll('₹', '')
        .replaceAll('-', ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _searchLooksNearby(String query) {
    final normalized = _normalizedText(query);
    if (normalized.isEmpty) return false;
    return normalized == 'seller near by me' ||
        normalized == 'sellers near by me' ||
        normalized == 'seller nearby me' ||
        normalized == 'sellers nearby me' ||
        normalized == 'near by me' ||
        normalized == 'nearby me' ||
        normalized == 'near me' ||
        normalized == 'nearby seller' ||
        normalized == 'nearby sellers' ||
        normalized == 'near seller' ||
        normalized == 'near sellers';
  }

  bool get _shouldUseNearbyFilter => selectedNearbyOnly || _searchLooksNearby(searchQuery);

  bool _matchesSearchText(Map<String, dynamic> product, String rawQuery) {
    final query = _normalizedText(rawQuery);
    if (query.isEmpty || _searchLooksNearby(query)) return true;

    final sellerName = _normalizedText(product['seller_name'] ?? product['shop_name'] ?? '');
    final productName = _normalizedText(product['prod_name'] ?? '');
    final categoryName = _normalizedText(product['category_name'] ?? '');
    final brandName = _normalizedText(product['brand'] ?? '');
    final stockStatus = _isOutOfStock(product) ? 'out of stock' : 'in stock';
    final nearbyText = product['is_nearby'] == true ? 'nearby' : 'not nearby';
    final price = _productPrice(product);
    final priceText = price % 1 == 0 ? price.toInt().toString() : price.toStringAsFixed(2);
    final tokens = query.split(' ').where((e) => e.trim().isNotEmpty).toList();

    bool matchesSingleToken(String token) {
      if (token == 'out' || token == 'stock') {
        return stockStatus.contains('out of stock');
      }
      if (token == 'in') {
        return stockStatus.contains('in stock');
      }
      if (token == 'nearby' || token == 'near') {
        return nearbyText.contains('nearby');
      }
      if (token == 'seller') {
        return sellerName.isNotEmpty;
      }
      if (sellerName.contains(token) ||
          productName.contains(token) ||
          categoryName.contains(token) ||
          brandName.contains(token) ||
          stockStatus.contains(token) ||
          nearbyText.contains(token) ||
          priceText.contains(token)) {
        return true;
      }

      final numeric = double.tryParse(token.replaceAll(',', ''));
      if (numeric != null) {
        return priceText.contains(token) || price == numeric;
      }
      return false;
    }

    return tokens.every(matchesSingleToken);
  }

  List<Map<String, dynamic>> get sellerFilterOptions {
    final map = <String, Map<String, dynamic>>{};
    for (final raw in products) {
      if (raw is! Map) continue;
      final product = Map<String, dynamic>.from(raw);
      final sellerId = int.tryParse((product['seller_id'] ?? '').toString());
      if (sellerId == null) continue;
      map.putIfAbsent('$sellerId', () => {
        'seller_id': sellerId,
        'seller_name': (product['seller_name'] ?? 'Seller').toString(),
      });
    }
    final list = map.values.toList();
    list.sort((a, b) => (a['seller_name'] as String)
        .toLowerCase()
        .compareTo((b['seller_name'] as String).toLowerCase()));
    return list;
  }

  List<String> get categoryFilterOptions {
    final set = <String>{};
    for (final raw in products) {
      if (raw is! Map) continue;
      final value = (raw['category_name'] ?? '').toString().trim();
      if (value.isNotEmpty) {
        set.add(value);
      }
    }
    final list = set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  List<Map<String, dynamic>> _applyFilters(List source) {
    final filtered = source
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((product) {
      final sellerId = int.tryParse((product['seller_id'] ?? '').toString());
      final categoryName = (product['category_name'] ?? '').toString().trim().toLowerCase();
      final price = _productPrice(product);

      if (!_matchesSearchText(product, searchQuery)) {
        return false;
      }

      if (selectedAvailability == 'in_stock' && _isOutOfStock(product)) {
        return false;
      }
      if (selectedAvailability == 'out_of_stock' && !_isOutOfStock(product)) {
        return false;
      }

      if (selectedNearbyOnly && product['is_nearby'] != true) {
        return false;
      }

      if (selectedSellerId != null && sellerId != selectedSellerId) {
        return false;
      }

      if (selectedCategoryName != 'all' &&
          categoryName != selectedCategoryName.trim().toLowerCase()) {
        return false;
      }

      if (selectedPriceRange == 'under_100' && price >= 100) {
        return false;
      }
      if (selectedPriceRange == '100_to_500' && (price < 100 || price > 500)) {
        return false;
      }
      if (selectedPriceRange == 'above_500' && price <= 500) {
        return false;
      }

      return true;
    }).toList();

    if (selectedSort == 'price_low_high') {
      filtered.sort((a, b) => _productPrice(a).compareTo(_productPrice(b)));
    } else if (selectedSort == 'price_high_low') {
      filtered.sort((a, b) => _productPrice(b).compareTo(_productPrice(a)));
    } else if (selectedSort == 'name_az') {
      filtered.sort((a, b) => (a['prod_name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['prod_name'] ?? '').toString().toLowerCase()));
    } else if (selectedSort == 'rating_high_low') {
      filtered.sort((a, b) {
        final ar = double.tryParse((a['avg_rating'] ?? 0).toString()) ?? 0;
        final br = double.tryParse((b['avg_rating'] ?? 0).toString()) ?? 0;
        return br.compareTo(ar);
      });
    }

    return filtered;
  }

  List<Map<String, dynamic>> get filteredSellers {
    final sellerRatings = <int, Map<String, dynamic>>{};

    for (final rawProduct in products) {
      if (rawProduct is! Map) continue;
      final product = Map<String, dynamic>.from(rawProduct);
      final sellerId = int.tryParse((product['seller_id'] ?? '').toString());
      if (sellerId == null || sellerId <= 0) continue;

      final rating = double.tryParse((product['avg_rating'] ?? 0).toString()) ?? 0;
      final reviewCount = int.tryParse((product['review_count'] ?? 0).toString()) ?? 0;

      if (!sellerRatings.containsKey(sellerId)) {
        sellerRatings[sellerId] = {
          'rating_sum': 0.0,
          'rating_count': 0,
          'review_count': 0,
        };
      }

      final sellerData = sellerRatings[sellerId]!;
      sellerData['rating_sum'] = (sellerData['rating_sum'] as double) + rating;
      sellerData['rating_count'] = (sellerData['rating_count'] as int) + 1;
      sellerData['review_count'] = (sellerData['review_count'] as int) + reviewCount;
    }

    final list = sellers
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((seller) {
      final sellerId = int.tryParse((seller['seller_id'] ?? '').toString());
      final sellerName = _normalizedText(seller['seller_name'] ?? '');
      final shopName = _normalizedText(seller['shop_name'] ?? '');
      final address = _normalizedText(seller['shop_address'] ?? '');
      final query = _normalizedText(searchQuery);

      if (sellerId == null || !sellerRatings.containsKey(sellerId)) {
        return false;
      }

      if (selectedNearbyOnly && seller['is_nearby'] != true) {
        return false;
      }

      if (selectedSellerId != null && sellerId != selectedSellerId) {
        return false;
      }

      if (query.isNotEmpty && !_searchLooksNearby(query)) {
        final tokens = query.split(' ').where((e) => e.trim().isNotEmpty).toList();
        final matches = tokens.every((token) =>
        sellerName.contains(token) || shopName.contains(token) || address.contains(token));
        if (!matches) {
          return false;
        }
      }

      return true;
    }).map((seller) {
      final sellerId = int.tryParse((seller['seller_id'] ?? '').toString()) ?? 0;
      final ratingData = sellerRatings[sellerId]!;
      final ratingCount = ratingData['rating_count'] as int;
      final ratingSum = ratingData['rating_sum'] as double;
      final avgRating = ratingCount > 0 ? (ratingSum / ratingCount) : 0.0;

      seller['avg_rating'] = avgRating;
      seller['review_count'] = ratingData['review_count'];
      return seller;
    }).toList();

    list.sort((a, b) {
      final aRating = double.tryParse((a['avg_rating'] ?? 0).toString()) ?? 0;
      final bRating = double.tryParse((b['avg_rating'] ?? 0).toString()) ?? 0;
      if (aRating != bRating) return bRating.compareTo(aRating);

      final aReviews = int.tryParse((a['review_count'] ?? 0).toString()) ?? 0;
      final bReviews = int.tryParse((b['review_count'] ?? 0).toString()) ?? 0;
      if (aReviews != bReviews) return bReviews.compareTo(aReviews);

      final aNearby = a['is_nearby'] == true ? 1 : 0;
      final bNearby = b['is_nearby'] == true ? 1 : 0;
      if (aNearby != bNearby) return bNearby.compareTo(aNearby);

      return (a['seller_name'] ?? '').toString().toLowerCase().compareTo(
        (b['seller_name'] ?? '').toString().toLowerCase(),
      );
    });

    return list.take(5).toList();
  }

  List<Map<String, dynamic>> get filteredProducts => _applyFilters(products);

  List<Map<String, dynamic>> get filteredNearbyProducts => _applyFilters(nearbyProducts);

  List<Map<String, dynamic>> get filteredOtherProducts => _applyFilters(otherProducts);

  bool get hasActiveFilters {
    return selectedPriceRange != 'all' ||
        selectedSort != 'default' ||
        selectedSellerId != null ||
        selectedCategoryName != 'all' ||
        selectedNearbyOnly;
  }

  void clearSearch() {
    searchController.clear();
    if (searchQuery.isNotEmpty && mounted) {
      setState(() {
        searchQuery = '';
      });
    }
    fetchHomeData();
  }

  void clearFilters() {
    setState(() {
      selectedAvailability = 'all';
      selectedPriceRange = 'all';
      selectedSort = 'default';
      selectedSellerId = null;
      selectedCategoryName = 'all';
      selectedNearbyOnly = false;
    });
  }

  Widget _buildAppliedChip(String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.blue.withOpacity(0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.blue,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget buildFilterChoice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.withOpacity(0.10) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.blue : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle : Icons.add,
              color: Colors.blue,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> openFilters() async {
    String tempPriceRange = selectedPriceRange;
    String tempSort = selectedSort;
    int? tempSellerId = selectedSellerId;
    String tempCategoryName = selectedCategoryName;
    bool tempNearbyOnly = selectedNearbyOnly;

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
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Filters',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                tempPriceRange = 'all';
                                tempSort = 'default';
                                tempSellerId = null;
                                tempCategoryName = 'all';
                                tempNearbyOnly = false;
                              });
                            },
                            child: const Text('Clear Filter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Category',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          buildFilterChoice(
                            label: 'All Categories',
                            selected: tempCategoryName == 'all',
                            onTap: () => setModalState(() => tempCategoryName = 'all'),
                          ),
                          ...categoryFilterOptions.map((category) {
                            return buildFilterChoice(
                              label: category,
                              selected: tempCategoryName.toLowerCase() == category.toLowerCase(),
                              onTap: () => setModalState(() => tempCategoryName = category),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Seller Distance',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          buildFilterChoice(
                            label: 'All',
                            selected: tempNearbyOnly == false,
                            onTap: () => setModalState(() => tempNearbyOnly = false),
                          ),
                          buildFilterChoice(
                            label: 'Seller Nearby',
                            selected: tempNearbyOnly == true,
                            onTap: () => setModalState(() => tempNearbyOnly = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Seller',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          buildFilterChoice(
                            label: 'All Sellers',
                            selected: tempSellerId == null,
                            onTap: () => setModalState(() => tempSellerId = null),
                          ),
                          ...sellerFilterOptions.map((seller) {
                            final sellerId = seller['seller_id'] as int?;
                            final sellerName = (seller['seller_name'] ?? 'Seller').toString();
                            return buildFilterChoice(
                              label: sellerName,
                              selected: tempSellerId == sellerId,
                              onTap: () => setModalState(() => tempSellerId = sellerId),
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Price Range',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          {'value': 'all', 'label': 'All'},
                          {'value': 'under_100', 'label': 'Below ₹100'},
                          {'value': '100_to_500', 'label': '₹100 - ₹500'},
                          {'value': 'above_500', 'label': 'Above ₹500'},
                        ].map((entry) {
                          return buildFilterChoice(
                            label: entry['label']!,
                            selected: tempPriceRange == entry['value'],
                            onTap: () => setModalState(() => tempPriceRange = entry['value']!),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Sort By',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          {'value': 'default', 'label': 'Default'},
                          {'value': 'price_low_high', 'label': 'Price low to high'},
                          {'value': 'price_high_low', 'label': 'Price high to low'},
                          {'value': 'name_az', 'label': 'Name A-Z'},
                          {'value': 'rating_high_low', 'label': 'Top Rated'},
                        ].map((entry) {
                          return buildFilterChoice(
                            label: entry['label']!,
                            selected: tempSort == entry['value'],
                            onTap: () => setModalState(() => tempSort = entry['value']!),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  selectedPriceRange = tempPriceRange;
                                  selectedSort = tempSort;
                                  selectedSellerId = tempSellerId;
                                  selectedCategoryName = tempCategoryName;
                                  selectedNearbyOnly = tempNearbyOnly;
                                });
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30),
                                ),
                              ),
                              child: const Text('Apply'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProductImage(Map product, {double width = 82, double height = 82}) {
    final imageUrl = _productImageUrl(product);
    if (imageUrl.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Icon(Icons.image_outlined, color: Colors.grey, size: width * 0.5),
      );
    }

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) {
        return SizedBox(
          width: width,
          height: height,
          child: Icon(Icons.image_outlined, color: Colors.grey, size: width * 0.5),
        );
      },
    );
  }

  Future<void> toggleWishlist(Map product) async {
    final next = await UserWishlistService.toggle(
      userId: currentUserId,
      wishlist: wishlist,
      product: Map<String, dynamic>.from(product),
    );

    wishlist
      ..clear()
      ..addAll(next);

    if (mounted) setState(() {});
  }

  Future<void> openWishlist() async {
    await refreshWishlist();

    final liveWishlist = wishlist
        .where((item) => item is Map)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WishlistPage(
          wishlist: liveWishlist,
          currentUserId: currentUserId,
          onUpdate: () async {
            await refreshWishlist();
          },
        ),
      ),
    );
    await refreshWishlist();
  }

  Future<void> openNotification() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationPage()),
    );
    await loadNotificationPreference();
    await fetchNotificationCount();
  }

  Future<void> openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    );
    await fetchProfileImage();
  }


  Widget _buildProductGrid(List productItems) {
    if (productItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('No products available')),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: productItems.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemBuilder: (context, index) {
        final product = Map<String, dynamic>.from(productItems[index]);
        final exists = UserWishlistService.contains(
          wishlist,
          product['prod_id'],
          sellerId: product['seller_id'],
        );
        final isOutOfStock = _isOutOfStock(product);

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => toggleWishlist(product),
                  child: Icon(
                    exists ? Icons.favorite : Icons.favorite_border,
                    color: exists ? Colors.red : Colors.grey,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProductDetailPage(
                              prodId: product['prod_id'],
                              sellerId: int.tryParse((product['seller_id'] ?? '').toString()),
                              wishlist: wishlist,
                              onUpdate: () {
                                setState(() {});
                              },
                            ),
                          ),
                        );
                        await refreshWishlist();
                      },
                      child: Center(child: _buildProductImage(product)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product['prod_name']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹ ${product['prod_price']}',
                    style: const TextStyle(color: Colors.green),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        '${double.tryParse((product['avg_rating'] ?? 0).toString())?.toStringAsFixed(1) ?? '0.0'} (${product['review_count'] ?? 0})',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (isOutOfStock)
                    const Text(
                      'Out of Stock',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => addToCart(
                          product['prod_id'],
                          sellerId: product['seller_id'],
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF1ECF8),
                          foregroundColor: Colors.deepPurple,
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        child: const Text('ADD'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget homePage() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () async {
        await refreshWishlist();
        await loadNotificationPreference();
        await fetchHomeData();
        await fetchNotificationCount();
      },
      child: ListView(
        children: [
          Container(
            color: Colors.blue,
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Search here...',
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.trim().isEmpty
                            ? null
                            : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: clearSearch,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: openFilters,
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: hasActiveFilters ? Colors.blue.shade200 : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.tune, color: hasActiveFilters ? Colors.blue : Colors.black87),
                        const SizedBox(width: 8),
                        Text(
                          'Filter',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: hasActiveFilters ? Colors.blue : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (selectedCategoryName != 'all')
                            _buildAppliedChip(selectedCategoryName),
                          if (selectedNearbyOnly)
                            _buildAppliedChip('Seller Nearby'),
                          if (selectedSellerId != null)
                            _buildAppliedChip(
                              sellerFilterOptions
                                  .firstWhere(
                                    (seller) => seller['seller_id'] == selectedSellerId,
                                orElse: () => {'seller_name': 'Seller'},
                              )['seller_name']
                                  ?.toString() ??
                                  'Seller',
                            ),
                          if (selectedPriceRange != 'all')
                            _buildAppliedChip(
                              selectedPriceRange == 'under_100'
                                  ? 'Below ₹100'
                                  : selectedPriceRange == '100_to_500'
                                  ? '₹100 - ₹500'
                                  : 'Above ₹500',
                            ),
                          if (selectedSort != 'default')
                            _buildAppliedChip(
                              selectedSort == 'price_low_high'
                                  ? 'Price low-high'
                                  : selectedSort == 'price_high_low'
                                  ? 'Price high-low'
                                  : selectedSort == 'name_az'
                                  ? 'Name A-Z'
                                  : 'Top Rated',
                            ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: clearFilters,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isNearbySearch ? 'Nearby Sellers' : 'Top Sellers',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: filteredSellers.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No sellers available')),
            )
                : SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: filteredSellers.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final seller = filteredSellers[index];
                  return GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SellerDetailPage(
                            sellerId: seller['seller_id'],
                            sellerName: seller['seller_name'],
                            wishlist: wishlist,
                            onUpdate: () {
                              setState(() {});
                            },
                          ),
                        ),
                      );
                      await refreshWishlist();
                    },
                    child: Container(
                      width: 145,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildSellerAvatar(seller, size: 56),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 36,
                            child: Center(
                              child: Text(
                                seller['seller_name']?.toString() ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _isNearbySearch ? 'Nearby Sellers Products' : 'Products',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: _buildProductGrid(_isNearbySearch ? filteredNearbyProducts : filteredProducts),
          ),
          if (_isNearbySearch && filteredOtherProducts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Other Products',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _buildProductGrid(filteredOtherProducts),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Desi Cart'),
        backgroundColor: Colors.blue,
        actions: [
          Stack(
            children: [
              IconButton(icon: const Icon(Icons.notifications_none), onPressed: openNotification),
              if (notificationsEnabled && notificationCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      '${notificationCount > 9 ? '9+' : notificationCount}',
                      style: const TextStyle(fontSize: 9, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.favorite_border),
                onPressed: openWishlist,
              ),
              if (wishlist.isNotEmpty)
                Positioned(
                  right: 6,
                  top: 6,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      '${wishlist.length > 9 ? '9+' : wishlist.length}',
                      style: const TextStyle(fontSize: 9, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
              child: profileImageUrl.isEmpty ? const Icon(Icons.person, color: Colors.blue) : null,
            ),
            onPressed: openProfile,
          ),
        ],
      ),
      body: homePage(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: (index) {
          if (index == currentIndex) return;
          if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => SellerPage(
                  wishlist: wishlist,
                  onUpdate: () {
                    setState(() {});
                  },
                ),
              ),
            );
            return;
          }
          if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CategoryPage(
                  wishlist: wishlist,
                  onUpdate: () {
                    setState(() {});
                  },
                ),
              ),
            );
            return;
          }
          if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CartScreen()),
            );
          }
        },
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Sellers'),
          BottomNavigationBarItem(icon: Icon(Icons.category), label: 'Category'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Cart'),
        ],
      ),
    );
  }
}