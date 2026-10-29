import 'dart:io';

import 'package:flutter/material.dart';
import 'package:product_inventory/model/store.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/storage_service.dart';
import 'package:product_inventory/shared/constant.dart';
import 'package:product_inventory/shared/image_picker_field.dart';

/// Create the seller's store, or edit it when [existing] is provided.
class StoreSetupScreen extends StatefulWidget {
  const StoreSetupScreen({super.key, required this.ownerId, this.existing});

  final String ownerId;
  final Store? existing;

  @override
  State<StoreSetupScreen> createState() => _StoreSetupScreenState();
}

class _StoreSetupScreenState extends State<StoreSetupScreen> {
  final DatabaseService _db = DatabaseService();
  final StorageService _storage = StorageService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late final TextEditingController _phoneController = TextEditingController(
    text: widget.existing?.phone ?? '',
  );
  late final TextEditingController _addressController = TextEditingController(
    text: widget.existing?.address ?? '',
  );
  late final TextEditingController _deliveryFeeController =
      TextEditingController(
        text: (widget.existing?.deliveryFee ?? 0).toStringAsFixed(2),
      );
  late final TextEditingController _leadTimeController = TextEditingController(
    text: (widget.existing?.leadTimeDays ?? 0).toString(),
  );
  late final TextEditingController _maxAdvanceController =
      TextEditingController(
        text: (widget.existing?.maxAdvanceDays ?? 30).toString(),
      );

  late bool _isOpen = widget.existing?.isOpen ?? true;
  late bool _pickupEnabled = widget.existing?.pickupEnabled ?? true;
  late bool _deliveryEnabled = widget.existing?.deliveryEnabled ?? true;
  late List<String> _closedDates = List<String>.of(
    widget.existing?.closedDates ?? const <String>[],
  )..sort();
  File? _logo;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _deliveryFeeController.dispose();
    _leadTimeController.dispose();
    _maxAdvanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      String? logoUrl = widget.existing?.logoUrl;
      final File? logo = _logo;
      if (logo != null) {
        logoUrl = await _storage.uploadImage(
          path: 'stores/${widget.ownerId}/logo',
          file: logo,
        );
      }

      await _db.saveStore(
        Store(
          ownerId: widget.ownerId,
          name: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          phone: _phoneController.text.trim(),
          address: _addressController.text.trim(),
          logoUrl: logoUrl,
          isOpen: _isOpen,
          pickupEnabled: _pickupEnabled,
          deliveryEnabled: _deliveryEnabled,
          deliveryFee: double.parse(_deliveryFeeController.text.trim()),
          leadTimeDays: int.parse(_leadTimeController.text.trim()),
          maxAdvanceDays: int.parse(_maxAdvanceController.text.trim()),
          closedDates: _closedDates,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save your store: $e')));
    }
  }

  String? _required(String? value, String message) {
    return (value == null || value.trim().isEmpty) ? message : null;
  }

  Future<void> _addClosedDate() async {
    final DateTime today = DateUtils.dateOnly(DateTime.now());
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 3),
    );
    if (!mounted || date == null) return;
    final String value =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    if (_closedDates.contains(value)) return;
    setState(() {
      _closedDates = <String>[..._closedDates, value]..sort();
    });
  }

  String? _feeValidator(String? value) {
    final double? fee = double.tryParse(value?.trim() ?? '');
    if (fee == null || !fee.isFinite || fee < 0 || fee > 1000000) {
      return 'Enter a delivery fee between 0 and 1,000,000';
    }
    return null;
  }

  String? _leadTimeValidator(String? value) {
    final int? days = int.tryParse(value?.trim() ?? '');
    if (days == null || days < 0 || days > 14) {
      return 'Enter lead time from 0 to 14 days';
    }
    final int? maxAdvance = int.tryParse(_maxAdvanceController.text.trim());
    if (maxAdvance != null && days > maxAdvance) {
      return 'Lead time cannot exceed the maximum advance period.';
    }
    return null;
  }

  String? _maxAdvanceValidator(String? value) {
    final int? days = int.tryParse(value?.trim() ?? '');
    if (days == null || days < 0 || days > 365) {
      return 'Enter maximum advance days from 0 to 365';
    }
    final int? leadTime = int.tryParse(_leadTimeController.text.trim());
    if (leadTime != null && days < leadTime) {
      return 'Maximum advance days cannot be less than lead time.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.existing != null;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F0),
      appBar: AppBar(
        backgroundColor: Colors.brown[100],
        title: Text(isEditing ? 'Edit store' : 'Set up your store'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: ImagePickerField(
                    pickedFile: _logo,
                    existingUrl: widget.existing?.logoUrl,
                    onPicked: (File file) => setState(() => _logo = file),
                    label: 'Store logo',
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Store name',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (String? v) => _required(v, 'Enter a store name'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'About your bakery (optional)',
                  ),
                  maxLines: 3,
                  maxLength: 500,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Contact number',
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      _required(v, 'Enter a contact number'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _addressController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Pickup address',
                  ),
                  maxLines: 2,
                  validator: (String? v) =>
                      _required(v, 'Enter your pickup address'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Store is open for orders'),
                  value: _isOpen,
                  onChanged: (bool v) => setState(() => _isOpen = v),
                ),
                const Divider(),
                Text(
                  'Fulfillment options',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pickup enabled'),
                  value: _pickupEnabled,
                  onChanged: (bool value) =>
                      setState(() => _pickupEnabled = value),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delivery enabled'),
                  value: _deliveryEnabled,
                  onChanged: (bool value) =>
                      setState(() => _deliveryEnabled = value),
                ),
                if (!_pickupEnabled && !_deliveryEnabled)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Enable at least one fulfillment option.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                TextFormField(
                  controller: _deliveryFeeController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Delivery fee',
                    prefixText: '₱ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _feeValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _leadTimeController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Lead time in days',
                    suffixText: 'days',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _leadTimeValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _maxAdvanceController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Maximum advance days',
                    suffixText: 'days',
                  ),
                  keyboardType: TextInputType.number,
                  validator: _maxAdvanceValidator,
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Customers can schedule orders from the lead time through this many days ahead.',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Closed dates',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving ? null : _addClosedDate,
                      icon: const Icon(Icons.add),
                      label: const Text('Add date'),
                    ),
                  ],
                ),
                if (_closedDates.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No dates marked closed.'),
                  ),
                for (final String date in _closedDates)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(date),
                    trailing: IconButton(
                      tooltip: 'Remove closed date',
                      icon: const Icon(Icons.close),
                      onPressed: _saving
                          ? null
                          : () => setState(() => _closedDates.remove(date)),
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving || (!_pickupEnabled && !_deliveryEnabled)
                      ? null
                      : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEditing ? 'Save changes' : 'Create store'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
