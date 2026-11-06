import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:product_inventory/model/address.dart';
import 'package:product_inventory/model/cart.dart';
import 'package:product_inventory/model/order.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/model/user.dart';
import 'package:product_inventory/screen/home/cart.dart';
import 'package:product_inventory/screen/home/order_confirmation.dart';
import 'package:product_inventory/screen/home/payment_waiting.dart';
import 'package:product_inventory/screen/account/profile_screen.dart'
    show AddressFormScreen, EditProfileScreen;
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/payment_service.dart';
import 'package:product_inventory/shared/app_theme.dart';
import 'package:product_inventory/shared/product_thumb.dart';
import 'package:product_inventory/shared/option_summary.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.items});

  final List<CartItem> items;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _isPaying = false;
  String _paymentMethod = 'cash';
  bool _loadingStores = true;
  String? _storeLoadError;
  late List<CartItem> _items;
  final DatabaseService _database = DatabaseService();
  final PaymentService _payments = PaymentService();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _discountCodeController = TextEditingController();
  double _discountAmount = 0;
  double? _validatedFinalTotal;
  final Map<String, Store> _stores = <String, Store>{};
  final Map<String, FulfillmentType> _fulfillmentTypes =
      <String, FulfillmentType>{};
  final Map<String, DateTime> _fulfillmentDates = <String, DateTime>{};
  final Map<String, String?> _selectedAddressIds = <String, String?>{};
  final Map<String, String?> _timeSlots = <String, String?>{};
  List<Address> _savedAddresses = <Address>[];

  @override
  void initState() {
    super.initState();
    _items = List<CartItem>.of(widget.items);
    _prepareCheckout();
  }

  Map<String, List<CartItem>> get _groups {
    final Map<String, List<CartItem>> groups = <String, List<CartItem>>{};
    for (final CartItem item in _items) {
      groups.putIfAbsent(item.sellerId, () => <CartItem>[]).add(item);
    }
    return groups;
  }

  double get _total {
    double total = 0;
    for (final MapEntry<String, List<CartItem>> group in _groups.entries) {
      total += group.value.fold<double>(
        0,
        (double sum, CartItem item) => sum + item.lineTotal,
      );
      if (_fulfillmentTypes[group.key] == FulfillmentType.delivery) {
        total += _stores[group.key]?.deliveryFee ?? 0;
      }
    }
    return total;
  }

  Future<void> _prepareCheckout() async {
    try {
      final List<CartItem> preparedItems = <CartItem>[];
      for (final CartItem item in _items) {
        final Product? product = await _database.getProductOnce(item.productId);
        if (!mounted) return;
        final String sellerId = (product?.sellerId ?? item.sellerId).trim();
        if (sellerId.isEmpty || product == null) {
          preparedItems.add(item);
          continue;
        }

        final Store? store =
            _stores[sellerId] ?? await _database.getStore(sellerId);
        if (!mounted) return;
        if (store == null) {
          preparedItems.add(item.copyWith(sellerId: sellerId));
          continue;
        }
        _stores[sellerId] = store;
        final CartItem prepared = item.copyWith(
          sellerId: sellerId,
          storeName: store.name,
        );
        if (prepared.sellerId != item.sellerId ||
            prepared.storeName != item.storeName) {
          await CartStore.instance.updateItem(prepared);
        }
        preparedItems.add(prepared);
      }
      if (!mounted) return;
      _items = preparedItems;
      final String? uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        _savedAddresses = await _database.getAddressesOnce(uid);
      }
      for (final String sellerId in _groups.keys) {
        final Store? store = _stores[sellerId];
        if (store == null) continue;
        final FulfillmentType type = store.pickupEnabled
            ? FulfillmentType.pickup
            : FulfillmentType.delivery;
        _fulfillmentTypes[sellerId] = type;
        _fulfillmentDates[sellerId] = _firstAvailableDate(store);
        final List<Address> defaults = _savedAddresses
            .where((Address address) => address.isDefault)
            .toList();
        _selectedAddressIds[sellerId] = defaults.isNotEmpty
            ? defaults.first.id
            : _savedAddresses.isNotEmpty
            ? _savedAddresses.first.id
            : null;
      }
      setState(() {
        _loadingStores = false;
        _storeLoadError = null;
      });
    } catch (error) {
      debugPrint('Checkout store options failed to load: $error');
      if (!mounted) return;
      setState(() {
        _loadingStores = false;
        _storeLoadError = 'Unable to load store fulfillment options: $error';
      });
    }
  }

  DateTime _firstAvailableDate(Store store) {
    DateTime candidate = DateUtils.dateOnly(
      DateTime.now().add(Duration(days: store.leadTimeDays)),
    );
    final DateTime lastDate = DateUtils.dateOnly(
      DateTime.now().add(Duration(days: store.maxAdvanceDays)),
    );
    while (!candidate.isAfter(lastDate)) {
      if (!_isClosedDate(store, candidate)) return candidate;
      candidate = candidate.add(const Duration(days: 1));
    }
    throw StateError('No available fulfillment dates are configured.');
  }

  bool _isClosedDate(Store store, DateTime date) =>
      store.closedDates.contains(_dateKey(date));

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _chooseDate(String sellerId, Store store) async {
    final DateTime firstDate = DateUtils.dateOnly(
      DateTime.now().add(Duration(days: store.leadTimeDays)),
    );
    final DateTime lastDate = DateUtils.dateOnly(
      DateTime.now().add(Duration(days: store.maxAdvanceDays)),
    );
    if (firstDate.isAfter(lastDate)) return;
    final DateTime? selected = await showDatePicker(
      context: context,
      initialDate: _fulfillmentDates[sellerId] ?? _firstAvailableDate(store),
      firstDate: firstDate,
      lastDate: lastDate,
      selectableDayPredicate: (DateTime date) => !_isClosedDate(store, date),
    );
    if (!mounted || selected == null) return;
    setState(() => _fulfillmentDates[sellerId] = DateUtils.dateOnly(selected));
  }

  @override
  void dispose() {
    _noteController.dispose();
    _discountCodeController.dispose();
    super.dispose();
  }

  Address? _selectedAddress(String sellerId) {
    final String? id = _selectedAddressIds[sellerId];
    for (final Address address in _savedAddresses) {
      if (address.id == id) return address;
    }
    return null;
  }

  Future<void> _addAddress(String sellerId) async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final String? savedAddressId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => AddressFormScreen(uid: uid)),
    );
    if (!mounted) return;
    final List<Address> addresses = await _database.getAddressesOnce(uid);
    if (!mounted) return;
    setState(() {
      _savedAddresses = addresses;
      final List<Address> defaults = addresses
          .where((Address address) => address.isDefault)
          .toList();
      final bool savedIdExists = addresses.any(
        (Address address) => address.id == savedAddressId,
      );
      _selectedAddressIds[sellerId] = savedIdExists
          ? savedAddressId
          : defaults.isNotEmpty
          ? defaults.first.id
          : (addresses.isEmpty ? null : addresses.last.id);
    });
  }

  bool _sameFulfillmentSettings(Store a, Store b) {
    if (a.pickupEnabled != b.pickupEnabled ||
        a.deliveryEnabled != b.deliveryEnabled ||
        a.deliveryFee != b.deliveryFee ||
        a.leadTimeDays != b.leadTimeDays ||
        a.maxAdvanceDays != b.maxAdvanceDays) {
      return false;
    }
    final List<String> aDates = List<String>.of(a.closedDates)..sort();
    final List<String> bDates = List<String>.of(b.closedDates)..sort();
    return listEquals(aDates, bDates);
  }

  Future<void> _pay() async {
    if (_isPaying) return;
    setState(() => _isPaying = true);
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('A signed-in user is required to complete the order.');
      }
      final UserData? profile = await _database.getUserProfile(user.uid);
      if (!mounted) return;
      if (profile == null) {
        throw StateError('Unable to load your customer profile.');
      }
      final String customerPhone = profile.phone?.trim() ?? '';
      if (customerPhone.isEmpty) {
        setState(() => _isPaying = false);
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => EditProfileScreen(uid: user.uid, profile: profile),
          ),
        );
        return;
      }

      final List<String> issues = <String>[];
      final List<CartItem> currentItems = <CartItem>[];
      final Map<String, Store?> stores = <String, Store?>{};
      final Set<String> changedStoreSettings = <String>{};

      for (final CartItem oldItem in _items) {
        final Product? product = await _database.getProductOnce(
          oldItem.productId,
        );
        if (!mounted) return;
        if (product == null) {
          await CartStore.instance.remove(oldItem.id);
          issues.add(
            '${oldItem.productName} is no longer available and was removed.',
          );
          continue;
        }

        final String sellerId = product.sellerId.trim();
        final Store? store = sellerId.isEmpty
            ? null
            : await _database.getStore(sellerId);
        if (!mounted) return;
        if (sellerId.isNotEmpty) {
          stores[sellerId] = store;
          final Store? previouslyLoaded = _stores[sellerId];
          if (previouslyLoaded != null &&
              store != null &&
              !_sameFulfillmentSettings(previouslyLoaded, store)) {
            changedStoreSettings.add(sellerId);
            issues.add(
              '${store.name} updated its fulfillment settings. Review the refreshed options before placing your order.',
            );
          }
          if (store != null) _stores[sellerId] = store;
        }

        final CartItem currentItem = CartItem(
          id: oldItem.id,
          productId: product.id,
          productName: product.name,
          price: product.price,
          sellerId: sellerId,
          storeName: store?.name ?? product.storeName,
          imageUrl: product.imageUrl,
          quantity: oldItem.quantity,
          selectedOptions: oldItem.selectedOptions,
          priceAdjustment: oldItem.priceAdjustment,
        );
        if (oldItem.productName != currentItem.productName ||
            oldItem.price != currentItem.price ||
            oldItem.sellerId != currentItem.sellerId ||
            oldItem.storeName != currentItem.storeName ||
            oldItem.imageUrl != currentItem.imageUrl) {
          await CartStore.instance.updateItem(currentItem);
        }
        currentItems.add(currentItem);

        if (sellerId.isEmpty) {
          issues.add(
            '${product.name} has no store linked. Remove and re-add it to your cart.',
          );
        } else if (!product.isAvailable) {
          issues.add('${product.name} is no longer available.');
        }
        if (product.stockQuantity != null &&
            oldItem.quantity > product.stockQuantity!) {
          issues.add(
            '${product.name} only has ${product.stockQuantity} in stock.',
          );
        }
        if (oldItem.price != product.price) {
          issues.add(
            '${product.name} now costs ${formatPeso(product.price)}; review the updated cart.',
          );
        }
        final String? optionIssue = _validateSelectedOptions(oldItem, product);
        final double currentAdjustment = _priceAdjustmentFor(
          oldItem.selectedOptions,
          product.optionGroups,
        );
        if (optionIssue != null) {
          issues.add('${product.name}: $optionIssue');
        } else if (oldItem.priceAdjustment != currentAdjustment) {
          issues.add(
            '${product.name} option pricing changed; review the updated cart.',
          );
        }
        if (sellerId.isNotEmpty && (store == null || !store.isOpen)) {
          issues.add(
            '${store?.name.isNotEmpty == true ? store!.name : 'A store'} is currently closed.',
          );
        }
        if (store != null) {
          final FulfillmentType? selectedType = _fulfillmentTypes[sellerId];
          final bool typeAvailable = selectedType == FulfillmentType.pickup
              ? store.pickupEnabled
              : selectedType == FulfillmentType.delivery
              ? store.deliveryEnabled
              : false;
          if (!typeAvailable) {
            issues.add(
              '${store.name} no longer offers the selected fulfillment method.',
            );
          }
          final DateTime? selectedDate = _fulfillmentDates[sellerId];
          final DateTime earliestDate = DateUtils.dateOnly(
            DateTime.now().add(Duration(days: store.leadTimeDays)),
          );
          final DateTime latestDate = DateUtils.dateOnly(
            DateTime.now().add(Duration(days: store.maxAdvanceDays)),
          );
          if (selectedDate == null ||
              selectedDate.isBefore(earliestDate) ||
              selectedDate.isAfter(latestDate) ||
              _isClosedDate(store, selectedDate)) {
            issues.add(
              'The selected date for ${store.name} is no longer available.',
            );
          }
          if (selectedType == FulfillmentType.delivery &&
              _selectedAddress(sellerId) == null) {
            issues.add('Choose a saved delivery address for ${store.name}.');
          }
          if (_timeSlots[sellerId] != null &&
              _timeSlots[sellerId] != 'morning' &&
              _timeSlots[sellerId] != 'afternoon') {
            issues.add('The selected time slot is invalid for ${store.name}.');
          }
        }
      }

      if (issues.isNotEmpty) {
        if (!mounted) return;
        _items = CartStore.instance.items;
        String? updatedScheduleError;
        final Map<String, DateTime> refreshedDates = <String, DateTime>{};
        for (final String sellerId in changedStoreSettings) {
          final Store? store = _stores[sellerId];
          if (store == null) continue;
          try {
            refreshedDates[sellerId] = _firstAvailableDate(store);
          } catch (error) {
            updatedScheduleError =
                'No available dates remain for ${store.name}: $error';
          }
        }
        setState(() {
          for (final String sellerId in changedStoreSettings) {
            final Store? store = _stores[sellerId];
            if (store == null) continue;
            if (_fulfillmentTypes[sellerId] == FulfillmentType.pickup &&
                !store.pickupEnabled) {
              _fulfillmentTypes[sellerId] = FulfillmentType.delivery;
            } else if (_fulfillmentTypes[sellerId] ==
                    FulfillmentType.delivery &&
                !store.deliveryEnabled) {
              _fulfillmentTypes[sellerId] = FulfillmentType.pickup;
            }
            final DateTime? refreshedDate = refreshedDates[sellerId];
            if (refreshedDate != null) {
              _fulfillmentDates[sellerId] = refreshedDate;
            }
          }
          if (updatedScheduleError != null) {
            _storeLoadError = updatedScheduleError;
          }
          _isPaying = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(issues.join('\n'))));
        return;
      }

      if (currentItems.isEmpty) {
        throw StateError('Your cart has no available products to order.');
      }

      final String storedCustomerName = profile.fullName;
      final String customerName = storedCustomerName.isNotEmpty
          ? storedCustomerName
          : user.displayName ?? user.email ?? user.uid;
      final String note = _noteController.text.trim();
      final List<Order> orders = <Order>[
        for (final MapEntry<String, List<CartItem>> group in _groupBySeller(
          currentItems,
        ).entries)
          _createOrder(
            group.key,
            group.value,
            stores[group.key],
            user.uid,
            customerName,
            customerPhone,
            note,
            _fulfillmentTypes[group.key]!,
            _fulfillmentDates[group.key]!,
            _selectedAddress(group.key),
            _timeSlots[group.key],
            paymentMethod: _paymentMethod,
          ),
      ];
      if (_paymentMethod == 'paymongo' && orders.length != 1) {
        throw StateError(
          'PayMongo checkout currently supports one seller order at a time. '
          'Choose cash on delivery for a multi-seller cart.',
        );
      }
      if (_discountCodeController.text.trim().isNotEmpty &&
          orders.length != 1) {
        throw StateError(
          'Discount codes currently apply to one seller order at a time.',
        );
      }
      final List<String> orderIds = await _database.placeOrders(orders);
      if (_discountCodeController.text.trim().isNotEmpty) {
        final ({double discountAmount, double finalTotal}) discount =
            await _payments.applyDiscount(
              orderIds.single,
              _discountCodeController.text.trim(),
            );
        _discountAmount = discount.discountAmount;
        _validatedFinalTotal = discount.finalTotal;
      }
      String? checkoutUrl;
      if (_paymentMethod == 'paymongo') {
        checkoutUrl = await _payments.createCheckout(orderIds.single);
        final bool opened = await _payments.openCheckout(checkoutUrl);
        if (!opened) {
          throw StateError('Could not open the PayMongo checkout page.');
        }
      }

      try {
        await CartStore.instance.clear();
      } catch (error) {
        debugPrint('Order placed, but the cart could not be cleared: $error');
      }

      if (!mounted) return;
      if (_paymentMethod == 'paymongo') {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => PaymentWaitingScreen(
              orderId: orderIds.single,
              checkoutUrl: checkoutUrl,
              result: 'pending',
            ),
          ),
        );
        return;
      }
      final double total = orders.fold<double>(
        0,
        (double sum, Order order) => sum + order.total,
      );
      final double finalTotal = _validatedFinalTotal ?? total - _discountAmount;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => OrderConfirmationScreen(
            orderCount: orders.length,
            total: finalTotal,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Checkout failed: $error');
      if (!mounted) return;
      setState(() => _isPaying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ProductDailyLimitException
                ? '${error.productName}: only ${error.remainingQuantity} remaining for that date.'
                : 'Order failed: $error',
          ),
        ),
      );
    }
  }

  String? _validateSelectedOptions(CartItem item, Product product) {
    final Set<String> currentGroupNames = product.optionGroups
        .map((ProductOptionGroup group) => group.name)
        .toSet();
    if (item.selectedOptions.keys.any(
      (String name) => !currentGroupNames.contains(name),
    )) {
      return 'some selected options are no longer available.';
    }
    for (final ProductOptionGroup group in product.optionGroups) {
      final Object? value = item.selectedOptions[group.name];
      if (group.type == ProductOptionType.singleChoice) {
        if (group.required && value == null) return 'choose ${group.name}.';
        if (value != null &&
            (value is! String ||
                !group.choices.any(
                  (ProductOptionChoice choice) => choice.label == value,
                ))) {
          return 'the selected ${group.name} option is no longer available.';
        }
      } else if (group.type == ProductOptionType.freeText) {
        if (group.required && (value is! String || value.trim().isEmpty)) {
          return 'enter ${group.name}.';
        }
        if (value != null && (value is! String || value.length > 100)) {
          return '${group.name} must be 100 characters or fewer.';
        }
      } else {
        if (group.required && (value is! List || value.isEmpty)) {
          return 'select at least one ${group.name} tag.';
        }
        if (value != null &&
            (value is! List ||
                value.any(
                  (Object? selected) => !group.choices.any(
                    (ProductOptionChoice choice) => choice.label == selected,
                  ),
                ))) {
          return 'a selected ${group.name} tag is no longer available.';
        }
      }
    }
    return null;
  }

  double _priceAdjustmentFor(
    Map<String, Object?> selections,
    List<ProductOptionGroup> groups,
  ) {
    return groups
        .where(
          (ProductOptionGroup group) =>
              group.type == ProductOptionType.singleChoice,
        )
        .fold<double>(0, (double total, ProductOptionGroup group) {
          final Object? selected = selections[group.name];
          for (final ProductOptionChoice choice in group.choices) {
            if (choice.label == selected) {
              return total + choice.priceAdjustment;
            }
          }
          return total;
        });
  }

  Map<String, List<CartItem>> _groupBySeller(List<CartItem> items) {
    final Map<String, List<CartItem>> groups = <String, List<CartItem>>{};
    for (final CartItem item in items) {
      groups.putIfAbsent(item.sellerId, () => <CartItem>[]).add(item);
    }
    return groups;
  }

  Order _createOrder(
    String sellerId,
    List<CartItem> items,
    Store? store,
    String customerId,
    String customerName,
    String customerPhone,
    String note,
    FulfillmentType fulfillmentType,
    DateTime fulfillmentDate,
    Address? address,
    String? timeSlot, {
    required String paymentMethod,
  }) {
    final List<OrderItem> orderItems = items
        .map(
          (CartItem item) => OrderItem(
            productId: item.productId,
            productName: item.productName,
            price: item.price,
            quantity: item.quantity,
            imageUrl: item.imageUrl,
            selectedOptions: item.selectedOptions,
            priceAdjustment: item.priceAdjustment,
          ),
        )
        .toList();
    final double subtotal = orderItems.fold<double>(
      0,
      (double sum, OrderItem item) => sum + item.lineTotal,
    );
    final String storeName = store?.name.isNotEmpty == true
        ? store!.name
        : items.first.storeName;
    final double deliveryFee = fulfillmentType == FulfillmentType.delivery
        ? store?.deliveryFee ?? 0
        : 0;
    return Order(
      id: '',
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      sellerId: sellerId,
      storeName: storeName,
      items: orderItems,
      subtotal: subtotal,
      total: subtotal + deliveryFee,
      deliveryFee: deliveryFee,
      fulfillment: OrderFulfillment(
        type: fulfillmentType,
        date: _dateKey(fulfillmentDate),
        timeSlot: timeSlot,
        address: fulfillmentType == FulfillmentType.delivery
            ? address?.toOrderMap()
            : null,
      ),
      note: note.isEmpty ? null : note,
      status: OrderStatus.pending,
      paymentMethod: paymentMethod,
      createdAt: null,
      updatedAt: null,
    );
  }

  Widget _buildFulfillment(String sellerId, Store store) {
    final List<FulfillmentType> availableTypes = <FulfillmentType>[
      if (store.pickupEnabled) FulfillmentType.pickup,
      if (store.deliveryEnabled) FulfillmentType.delivery,
    ];
    final FulfillmentType? selectedType = _fulfillmentTypes[sellerId];
    final DateTime? selectedDate = _fulfillmentDates[sellerId];
    final Address? selectedAddress = _selectedAddress(sellerId);
    final List<String> closedDates = List<String>.of(store.closedDates)..sort();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Fulfillment',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (availableTypes.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'This store has no fulfillment options enabled.',
                style: TextStyle(color: Colors.red),
              ),
            )
          else
            SegmentedButton<FulfillmentType>(
              segments: <ButtonSegment<FulfillmentType>>[
                for (final FulfillmentType type in availableTypes)
                  ButtonSegment<FulfillmentType>(
                    value: type,
                    label: Text(type.label),
                    icon: Icon(
                      type == FulfillmentType.pickup
                          ? Icons.storefront_outlined
                          : Icons.local_shipping_outlined,
                    ),
                  ),
              ],
              selected: <FulfillmentType>{
                if (selectedType != null &&
                    availableTypes.contains(selectedType))
                  selectedType
                else
                  availableTypes.first,
              },
              onSelectionChanged: _isPaying
                  ? null
                  : (Set<FulfillmentType> selection) => setState(
                      () => _fulfillmentTypes[sellerId] = selection.first,
                    ),
            ),
          const SizedBox(height: 8),
          Text(
            'Available from ${store.leadTimeDays} day(s) ahead; schedule up to ${store.maxAdvanceDays} days ahead.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Closed dates: ${closedDates.isEmpty ? 'none' : closedDates.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (selectedType == FulfillmentType.delivery)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Delivery fee: ${formatPeso(store.deliveryFee)}'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isPaying ? null : () => _chooseDate(sellerId, store),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text(
              selectedDate == null
                  ? 'Choose fulfillment date'
                  : 'Date: ${_dateKey(selectedDate)}',
            ),
          ),
          DropdownButtonFormField<String?>(
            initialValue: _timeSlots[sellerId],
            decoration: const InputDecoration(
              labelText: 'Preferred time (optional)',
            ),
            items: const <DropdownMenuItem<String?>>[
              DropdownMenuItem<String?>(value: null, child: Text('Any time')),
              DropdownMenuItem<String?>(
                value: 'morning',
                child: Text('Morning'),
              ),
              DropdownMenuItem<String?>(
                value: 'afternoon',
                child: Text('Afternoon'),
              ),
            ],
            onChanged: _isPaying
                ? null
                : (String? value) =>
                      setState(() => _timeSlots[sellerId] = value),
          ),
          if (selectedType == FulfillmentType.delivery)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_savedAddresses.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue:
                          _savedAddresses.any(
                            (Address address) =>
                                address.id == _selectedAddressIds[sellerId],
                          )
                          ? _selectedAddressIds[sellerId]
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Delivery address',
                      ),
                      items: <DropdownMenuItem<String>>[
                        for (final Address address in _savedAddresses)
                          DropdownMenuItem<String>(
                            value: address.id,
                            child: Text(
                              '${address.label}${address.isDefault ? ' (Default)' : ''}',
                            ),
                          ),
                      ],
                      onChanged: _isPaying
                          ? null
                          : (String? id) => setState(
                              () => _selectedAddressIds[sellerId] = id,
                            ),
                    ),
                  if (selectedAddress != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      '${selectedAddress.recipient} · ${selectedAddress.phone}\n${selectedAddress.oneLine}',
                    ),
                    if (selectedAddress.notes?.isNotEmpty == true)
                      Text('Note: ${selectedAddress.notes}'),
                  ],
                  OutlinedButton.icon(
                    onPressed: _isPaying ? null : () => _addAddress(sellerId),
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(
                      _savedAddresses.isEmpty
                          ? 'Add a delivery address'
                          : 'Add a new address',
                    ),
                  ),
                ],
              ),
            ),
          if (selectedType == FulfillmentType.pickup) ...<Widget>[
            const SizedBox(height: 8),
            Text('Pickup at: ${store.address}'),
            Text('Store phone: ${store.phone}'),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, List<CartItem>> groups = _groups;
    return Scaffold(
      appBar: AppBar(title: const Text('Order Now')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: _loadingStores
                    ? const Center(child: CircularProgressIndicator())
                    : _storeLoadError != null
                    ? Center(child: Text(_storeLoadError!))
                    : _items.isEmpty
                    ? const Center(child: Text('Your cart is empty.'))
                    : ListView(
                        children: <Widget>[
                          for (final MapEntry<String, List<CartItem>> group
                              in groups.entries) ...<Widget>[
                            Text(
                              'Order from ${group.value.first.storeName.isEmpty ? 'Store details needed' : group.value.first.storeName}',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            for (final CartItem item in group.value)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ProductThumb(url: item.imageUrl),
                                title: Text(item.productName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '${formatPeso(item.price + item.priceAdjustment)} × ${item.quantity}',
                                    ),
                                    OptionSummary(
                                      options: item.selectedOptions,
                                    ),
                                  ],
                                ),
                                trailing: Text(formatPeso(item.lineTotal)),
                              ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                const Text('Store subtotal'),
                                Text(
                                  formatPeso(
                                    group.value.fold<double>(
                                      0,
                                      (double sum, CartItem item) =>
                                          sum + item.lineTotal,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_fulfillmentTypes[group.key] ==
                                FulfillmentType.delivery) ...<Widget>[
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  const Text('Delivery fee'),
                                  Text(
                                    formatPeso(
                                      _stores[group.key]?.deliveryFee ?? 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                const Text('Store total'),
                                Text(
                                  formatPeso(
                                    group.value.fold<double>(
                                          0,
                                          (double sum, CartItem item) =>
                                              sum + item.lineTotal,
                                        ) +
                                        (_fulfillmentTypes[group.key] ==
                                                FulfillmentType.delivery
                                            ? (_stores[group.key]
                                                      ?.deliveryFee ??
                                                  0)
                                            : 0),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            if (_stores[group.key] case final Store store)
                              _buildFulfillment(group.key, store),
                            if (_stores[group.key] == null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  'Could not load this store. Remove and re-add these items.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                          ],
                          TextField(
                            controller: _noteController,
                            enabled: !_isPaying,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Note to seller (optional)',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (groups.length == 1) ...<Widget>[
                            TextField(
                              controller: _discountCodeController,
                              enabled: !_isPaying,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Discount code (optional)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          const Text(
                            'Payment method',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          SegmentedButton<String>(
                            segments: <ButtonSegment<String>>[
                              const ButtonSegment<String>(
                                value: 'cash',
                                label: Text('Cash'),
                                icon: Icon(Icons.payments_outlined),
                              ),
                              if (groups.length == 1)
                                const ButtonSegment<String>(
                                  value: 'paymongo',
                                  label: Text('PayMongo'),
                                  icon: Icon(Icons.credit_card_outlined),
                                ),
                            ],
                            selected: <String>{_paymentMethod},
                            onSelectionChanged: _isPaying
                                ? null
                                : (Set<String> selection) => setState(
                                    () => _paymentMethod = selection.first,
                                  ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            groups.length > 1
                                ? 'PayMongo is available for one seller order at a time.'
                                : 'PayMongo is a test checkout; payment is confirmed by webhook.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Text(kShippingNote),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  const Text(
                    'Grand total',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    formatPeso(
                      _validatedFinalTotal ?? _total - _discountAmount,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _paymentMethod == 'paymongo'
                    ? 'PayMongo test checkout opens in your browser. Returning to the app does not confirm payment; only a verified webhook does.'
                    : 'Cash on delivery/pickup. No payment is processed in the app.',
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed:
                    _isPaying ||
                        _loadingStores ||
                        _storeLoadError != null ||
                        _items.isEmpty
                    ? null
                    : _pay,
                icon: _isPaying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.receipt_long_outlined),
                label: Text(
                  _isPaying
                      ? 'Processing...'
                      : _paymentMethod == 'paymongo'
                      ? 'Continue to PayMongo'
                      : 'Place Order',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
