import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/api_config.dart';
import 'package:my_app/screens/token_storage.dart';
import 'package:my_app/user/user_auth_session.dart';
import 'package:my_app/user/user_category_page.dart';
import 'package:my_app/user/user_home_page.dart';
import 'package:my_app/user/user_order_summary_page.dart';
import 'package:my_app/user/user_product_detail_page.dart';
import 'package:my_app/user/user_seller_page.dart';

class CartItem {
  final int cartId;
  final int prodId;
  final int? sellerId;
  final String name;
  final String image;
  final double price;
  final String brand;
  final String description;
  final String seller;
  final double stockQuantity;
  final String stockStatus;
  int quantity;

  CartItem({
    required this.cartId,
    required this.prodId,
    required this.sellerId,
    required this.name,
    required this.image,
    required this.price,
    required this.brand,
    required this.description,
    required this.seller,
    required this.stockQuantity,
    required this.stockStatus,
    required this.quantity,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      cartId: int.tryParse(json['cart_id'].toString()) ?? 0,
      prodId: int.tryParse(json['prod_id'].toString()) ?? 0,
      sellerId: json['seller_id'] == null ? null : int.tryParse(json['seller_id'].toString()),
      name: (json['prod_name'] ?? '').toString(),
      image: (json['prod_image'] ?? '').toString(),
      price: double.tryParse((json['prod_price'] ?? json['price_at_time'] ?? 0).toString()) ?? 0,
      brand: (json['brand'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      seller: (json['seller_name'] ?? '').toString(),
      stockQuantity: double.tryParse((json['stock_quantity'] ?? 0).toString()) ?? 0,
      stockStatus: (json['stock_status'] ?? '').toString(),
      quantity: int.tryParse((json['quantity'] ?? 1).toString()) ?? 1,
    );
  }

  bool get isOutOfStock {
    final status = stockStatus.trim().toLowerCase();
    return status == 'out of stock' || stockQuantity <= 0;
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  int? userId;
  List<CartItem> cartItems = [];
  int currentIndex = 3;
  bool isLoading = true;

  final TextEditingController searchController = TextEditingController();
  String searchQuery = '';
  String selectedAvailability = 'all';
  int? selectedSellerId;
  String selectedPriceRange = 'all';
  String selectedSort = 'default';

  @override
  void initState() {
    super.initState();
    initData();
    searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        searchQuery = searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> initData() async {
    userId = await UserAuthSession.getCurrentUserId();
    if (userId != null) {
      await fetchCart();
    } else if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<Map<String, String>> getHeaders() async {
    final token = await TokenStorage().getAccessToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> fetchCart() async {
    final res = await http.get(
      ApiConfig.uri('/get_cart/${userId ?? 0}'),
      headers: await getHeaders(),
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      setState(() {
        cartItems = data
            .map((e) => CartItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        isLoading = false;
      });
    } else {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> buyNow(CartItem item) async {
    if (item.isOutOfStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This product is currently out of stock.')),
      );
      return;
    }

    final res = await http.post(
      ApiConfig.uri('/buy_now'),
      headers: await getHeaders(),
      body: jsonEncode({
        'prod_id': item.prodId,
        if (item.sellerId != null) 'seller_id': item.sellerId,
        'quantity': item.quantity,
      }),
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderSummaryPage(singleItem: data['items'][0]),
        ),
      );
    } else {
      String message = 'Unable to buy this product right now';
      try {
        final data = jsonDecode(res.body);
        message = (data['message'] ?? message).toString();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> updateQuantity(CartItem item, int qty) async {
    if (qty <= 0) return;

    if (qty > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Max 10 allowed')),
      );
      return;
    }

    final res = await http.post(
      ApiConfig.uri('/update_cart'),
      headers: await getHeaders(),
      body: jsonEncode({
        'cart_id': item.cartId,
        'quantity': qty,
      }),
    );

    if (!mounted) return;

    if (res.statusCode != 200) {
      String message = 'Unable to update quantity';
      try {
        final data = jsonDecode(res.body);
        message = (data['message'] ?? message).toString();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }

    await fetchCart();
  }

  Future<void> removeItem(int cartId) async {
    await http.delete(
      ApiConfig.uri('/remove_cart/$cartId'),
      headers: await getHeaders(),
    );
    await fetchCart();
  }

  void showQtyPopup(CartItem item) {
    final controller = TextEditingController(text: item.quantity.toString());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final qty = int.tryParse(controller.text) ?? item.quantity;
              Navigator.pop(context);
              updateQuantity(item, qty);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  double get subtotal => cartItems.fold(0, (sum, item) => sum + item.price * item.quantity);
  double get discount => 0;
  double get platformFee => cartItems.isEmpty ? 0 : 7;
  double get deliveryStaffFee => cartItems.isEmpty ? 0 : 20;
  double get total => subtotal + platformFee + deliveryStaffFee;
  bool get hasOutOfStockItems => cartItems.any((item) => item.isOutOfStock);

  List<Map<String, dynamic>> get sellerOptions {
    final sellers = <String, Map<String, dynamic>>{};
    for (final item in cartItems) {
      final sellerId = item.sellerId;
      if (sellerId == null) continue;
      sellers.putIfAbsent('$sellerId', () => {
        'seller_id': sellerId,
        'seller_name': item.seller.trim().isEmpty ? 'Seller' : item.seller,
      });
    }
    final list = sellers.values.toList();
    list.sort((a, b) => (a['seller_name'] as String).toLowerCase().compareTo((b['seller_name'] as String).toLowerCase()));
    return list;
  }

  List<CartItem> get filteredCartItems {
    final filtered = cartItems.where((item) {
      final combinedText = [item.name, item.brand, item.description, item.seller]
          .join(' ')
          .toLowerCase();

      if (searchQuery.isNotEmpty && !combinedText.contains(searchQuery)) {
        return false;
      }

      if (selectedAvailability == 'available' && item.isOutOfStock) {
        return false;
      }
      if (selectedAvailability == 'out_of_stock' && !item.isOutOfStock) {
        return false;
      }

      if (selectedSellerId != null && item.sellerId != selectedSellerId) {
        return false;
      }

      if (selectedPriceRange == 'under_100' && item.price >= 100) {
        return false;
      }
      if (selectedPriceRange == '100_to_500' && (item.price < 100 || item.price > 500)) {
        return false;
      }
      if (selectedPriceRange == 'above_500' && item.price <= 500) {
        return false;
      }

      return true;
    }).toList();

    if (selectedSort == 'price_low_high') {
      filtered.sort((a, b) => a.price.compareTo(b.price));
    } else if (selectedSort == 'price_high_low') {
      filtered.sort((a, b) => b.price.compareTo(a.price));
    } else if (selectedSort == 'quantity_high_low') {
      filtered.sort((a, b) => b.quantity.compareTo(a.quantity));
    } else if (selectedSort == 'name_az') {
      filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return filtered;
  }

  bool get hasActiveFilters {
    return searchQuery.isNotEmpty ||
        selectedAvailability != 'all' ||
        selectedSellerId != null ||
        selectedPriceRange != 'all' ||
        selectedSort != 'default';
  }

  void clearFilters() {
    setState(() {
      searchController.clear();
      searchQuery = '';
      selectedAvailability = 'all';
      selectedSellerId = null;
      selectedPriceRange = 'all';
      selectedSort = 'default';
    });
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
    String tempAvailability = selectedAvailability;
    int? tempSellerId = selectedSellerId;
    String tempPriceRange = selectedPriceRange;
    String tempSort = selectedSort;

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
                                tempAvailability = 'all';
                                tempSellerId = null;
                                tempPriceRange = 'all';
                                tempSort = 'default';
                              });
                            },
                            child: const Text('Clear Filter'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Availability',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          {'value': 'all', 'label': 'All'},
                          {'value': 'available', 'label': 'Available'},
                          {'value': 'out_of_stock', 'label': 'Out of Stock'},
                        ].map((entry) {
                          return buildFilterChoice(
                            label: entry['label']!,
                            selected: tempAvailability == entry['value'],
                            onTap: () => setModalState(() => tempAvailability = entry['value']!),
                          );
                        }).toList(),
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
                          ...sellerOptions.map((seller) {
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
                          {'value': 'quantity_high_low', 'label': 'Qty high to low'},
                          {'value': 'name_az', 'label': 'Name A-Z'},
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
                                  selectedAvailability = tempAvailability;
                                  selectedSellerId = tempSellerId;
                                  selectedPriceRange = tempPriceRange;
                                  selectedSort = tempSort;
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

  Widget _buildTopSearchAndFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search cart items...',
                        prefixIcon: Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: openFilters,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: hasActiveFilters ? Colors.blue : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.tune,
                        color: hasActiveFilters ? Colors.blue : Colors.black87,
                      ),
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
          if (hasActiveFilters) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (selectedAvailability != 'all')
                          _buildAppliedChip(
                            selectedAvailability == 'available' ? 'Available' : 'Out of Stock',
                          ),
                        if (selectedSellerId != null)
                          _buildAppliedChip(
                            sellerOptions
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
                                : selectedSort == 'quantity_high_low'
                                ? 'Qty high-low'
                                : 'Name A-Z',
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
          ],
        ],
      ),
    );
  }

  Widget _buildAppliedChip(String label) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
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

  Widget _buildResultSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Row(
        children: [
          Text(
            'Showing ${filteredCartItems.length} of ${cartItems.length} items',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _goToHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
    );
  }

  void onNavTap(int index) {
    if (index == currentIndex) return;

    if (index == 0) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
            (route) => false,
      );
    } else if (index == 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SellerPage(wishlist: const [], onUpdate: () {}),
        ),
      );
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CategoryPage(
            wishlist: const [],
            onUpdate: () {},
          ),
        ),
      );
    }
  }

  Widget _buildImage(CartItem item) {
    final url = item.image.trim();
    if (url.isEmpty) {
      return Container(
        width: 82,
        height: 82,
        alignment: Alignment.center,
        color: Colors.grey.shade100,
        child: const Icon(Icons.image_outlined, color: Colors.grey),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        url.startsWith('http') ? url : ApiConfig.fileUrl(url),
        width: 82,
        height: 82,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            width: 82,
            height: 82,
            alignment: Alignment.center,
            color: Colors.grey.shade100,
            child: const Icon(Icons.image_outlined, color: Colors.grey),
          );
        },
      ),
    );
  }


  Future<void> _openProductDetails(CartItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailPage(
          prodId: item.prodId,
          sellerId: item.sellerId,
          initialProduct: {
            'prod_id': item.prodId,
            if (item.sellerId != null) 'seller_id': item.sellerId,
            'prod_name': item.name,
            'prod_image': item.image,
            'prod_price': item.price,
            'brand': item.brand,
            'description': item.description,
            'seller_name': item.seller,
            'stock_quantity': item.stockQuantity,
            'stock_status': item.stockStatus,
          },
          wishlist: const [],
          onUpdate: () {},
        ),
      ),
    );

    if (mounted) {
      await fetchCart();
    }
  }

  Widget _buildCartItemCard(CartItem item) {
    final dropdownValue = item.quantity > 5 ? 'More' : item.quantity.toString();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openProductDetails(item),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildImage(item),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        if (item.brand.trim().isNotEmpty) Text('Brand: ${item.brand}'),
                        if (item.description.trim().isNotEmpty)
                          Text(
                            item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (item.seller.trim().isNotEmpty) Text('Seller: ${item.seller}'),
                        const SizedBox(height: 6),
                        Text(
                          '₹ ${item.price.toStringAsFixed(1)}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.isOutOfStock ? 'Out of Stock' : 'Available',
                          style: TextStyle(
                            color: item.isOutOfStock ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Qty: '),
                            DropdownButton<String>(
                              value: dropdownValue,
                              items: [
                                ...List.generate(5, (i) => (i + 1).toString()),
                                'More',
                              ]
                                  .map(
                                    (e) => DropdownMenuItem<String>(
                                  value: e,
                                  child: Text(e),
                                ),
                              )
                                  .toList(),
                              onChanged: (val) {
                                if (val == 'More') {
                                  showQtyPopup(item);
                                } else if (val != null) {
                                  updateQuantity(item, int.parse(val));
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton(
                  onPressed: () => removeItem(item.cartId),
                  child: const Text('Remove'),
                ),
                TextButton(
                  onPressed: item.isOutOfStock ? null : () => buyNow(item),
                  child: Text(item.isOutOfStock ? 'Cannot buy now' : 'Buy this now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _goToOrderSummary() async {
    if (hasOutOfStockItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remove out-of-stock products or wait until they are available before placing the order.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const OrderSummaryPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = filteredCartItems;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _goToHome();
      },
      child: Scaffold(
        backgroundColor: const Color(0xfff3edf7),
        appBar: AppBar(
          backgroundColor: Colors.blue,
          title: const Text('Cart Page'),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : cartItems.isEmpty
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Your cart is empty'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false,
                  );
                },
                child: const Text('Continue Shopping'),
              ),
            ],
          ),
        )
            : RefreshIndicator(
          onRefresh: fetchCart,
          child: ListView(
            padding: const EdgeInsets.only(top: 10, bottom: 18),
            children: [
              if (hasOutOfStockItems)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Text(
                    'Some products in your cart are currently out of stock. They will stay in the cart, but you can buy them only after they become available again.',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              _buildTopSearchAndFilter(),
              _buildResultSummary(),
              if (visibleItems.isEmpty)
                Container(
                  margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.search_off, size: 42, color: Colors.grey),
                      const SizedBox(height: 10),
                      const Text(
                        'No cart items found',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Try changing your search or filters.',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                )
              else
                ...visibleItems.map(_buildCartItemCard),
              GestureDetector(
                onTap: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const HomePage()),
                        (route) => false,
                  );
                },
                child: Container(
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Center(
                    child: Text(
                      '+ Add more items',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(15),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Price Details',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Price (${cartItems.length} items)'),
                        Text('₹ ${subtotal.toStringAsFixed(0)}'),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Discount"),
                        Text("- ₹ ${discount.toStringAsFixed(0)}"),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Platform Fee"),
                        Text("₹ ${platformFee.toStringAsFixed(0)}"),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Delivery Staff Fee"),
                        Text("₹ ${deliveryStaffFee.toStringAsFixed(0)}"),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Total Amount",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "₹ ${total.toStringAsFixed(0)}",
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "₹ ${total.toStringAsFixed(0)}",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                      onPressed: _goToOrderSummary,
                      child: const Text("Place Order"),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onNavTap,
          selectedItemColor: Colors.blue,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
            BottomNavigationBarItem(icon: Icon(Icons.store), label: "Seller"),
            BottomNavigationBarItem(icon: Icon(Icons.category), label: "Category"),
            BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: "Cart"),
          ],
        ),
      ),
    );
  }
}