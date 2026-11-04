import 'dart:io';

import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/storage_service.dart';
import 'package:product_inventory/shared/constant.dart';
import 'package:product_inventory/shared/image_picker_field.dart';

/// Add a product, or edit it when [product] is provided.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.sellerId,
    required this.storeName,
    this.product,
  });

  final String sellerId;
  final String storeName;
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final DatabaseService _db = DatabaseService();
  final StorageService _storage = StorageService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController = TextEditingController(
    text: widget.product?.name ?? '',
  );
  late final TextEditingController _priceController = TextEditingController(
    text: widget.product == null
        ? ''
        : widget.product!.price.toStringAsFixed(2),
  );
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.product?.description ?? '');
  late final TextEditingController _maxPerDayController = TextEditingController(
    text: widget.product?.maxPerDay?.toString() ?? '',
  );
  late final TextEditingController _stockController = TextEditingController(
    text: widget.product?.stockQuantity?.toString() ?? '0',
  );

  late final String _productId = widget.product?.id ?? _db.newProductId();
  late String _category =
      ProductCategories.all.contains(widget.product?.category)
      ? widget.product!.category
      : ProductCategories.all.first;
  late bool _isAvailable = widget.product?.isAvailable ?? true;
  late List<ProductOptionGroup> _optionGroups = List<ProductOptionGroup>.of(
    widget.product?.optionGroups ?? const <ProductOptionGroup>[],
  );
  late List<int> _optionGroupIds = List<int>.generate(
    _optionGroups.length,
    (int index) => index,
  );
  late int _nextOptionGroupId = _optionGroups.length;

  File? _image;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _maxPerDayController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final String? optionsError = _validateOptionGroups();
    if (optionsError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(optionsError)));
      return;
    }
    setState(() => _saving = true);

    try {
      String? imageUrl = widget.product?.imageUrl;
      final File? image = _image;
      if (image != null) {
        imageUrl = await _storage.uploadImage(
          path: 'stores/${widget.sellerId}/products/$_productId',
          file: image,
        );
      }

      await _db.saveProduct(
        Product(
          id: _productId,
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          description: _descriptionController.text.trim(),
          imageUrl: imageUrl,
          sellerId: widget.sellerId,
          storeName: widget.storeName,
          category: _category,
          isAvailable: _isAvailable,
          maxPerDay: _maxPerDayController.text.trim().isEmpty
              ? null
              : int.parse(_maxPerDayController.text.trim()),
          stockQuantity: int.parse(_stockController.text.trim()),
          optionGroups: _optionGroups,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save the product: $e')));
    }
  }

  String? _validateOptionGroups() {
    final Set<String> names = <String>{};
    for (final ProductOptionGroup group in _optionGroups) {
      if (group.name.trim().isEmpty || group.name.length > 50) {
        return 'Each option group needs a name of 1 to 50 characters.';
      }
      if (!names.add(group.name.toLowerCase())) {
        return 'Option group names must be unique.';
      }
      if (group.type != ProductOptionType.freeText && group.choices.isEmpty) {
        return '${group.name} needs at least one choice.';
      }
      final Set<String> choiceNames = <String>{};
      for (final ProductOptionChoice choice in group.choices) {
        if (choice.label.isEmpty ||
            choice.label.length > 60 ||
            !choiceNames.add(choice.label.toLowerCase()) ||
            !choice.priceAdjustment.isFinite ||
            choice.priceAdjustment < 0) {
          return 'Check the choices and price adjustments for ${group.name}.';
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditing = widget.product != null;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF8F0),
      appBar: AppBar(
        backgroundColor: Colors.brown[100],
        title: Text(isEditing ? 'Edit product' : 'New product'),
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
                    pickedFile: _image,
                    existingUrl: widget.product?.imageUrl,
                    onPicked: (File file) => setState(() => _image = file),
                    size: 180,
                    label: 'Product photo',
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Product name',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (String? v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Price (₱)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (String? v) {
                    final double? price = double.tryParse((v ?? '').trim());
                    if (price == null || price <= 0) {
                      return 'Enter a price greater than 0';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _category,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Category',
                  ),
                  items: ProductCategories.all
                      .map(
                        (String c) =>
                            DropdownMenuItem<String>(value: c, child: Text(c)),
                      )
                      .toList(),
                  onChanged: (String? c) {
                    if (c != null) setState(() => _category = c);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Description, ingredients, allergens (optional)',
                  ),
                  maxLines: 4,
                  maxLength: 500,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxPerDayController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Daily order limit (optional)',
                    helperText: 'Leave empty for unlimited orders per day.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (String? value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    final int? limit = int.tryParse(value!.trim());
                    if (limit == null || limit < 1 || limit > 10000) {
                      return 'Enter a whole number from 1 to 10,000';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _stockController,
                  decoration: textInputDecoration.copyWith(
                    hintText: 'Stock quantity',
                    helperText: 'Set to 0 to mark the product out of stock.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (String? value) {
                    final int? stock = int.tryParse((value ?? '').trim());
                    if (stock == null || stock < 0 || stock > 1000000) {
                      return 'Enter a whole number from 0 to 1,000,000';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Product options',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                              _optionGroups = <ProductOptionGroup>[
                                ..._optionGroups,
                                const ProductOptionGroup(
                                  name: '',
                                  type: ProductOptionType.singleChoice,
                                ),
                              ];
                              _optionGroupIds = <int>[
                                ..._optionGroupIds,
                                _nextOptionGroupId++,
                              ];
                            }),
                      icon: const Icon(Icons.add),
                      label: const Text('Add group'),
                    ),
                  ],
                ),
                const Text(
                  'Choices use one per line. For extra prices, enter Label|amount (for example Large|50).',
                ),
                for (int index = 0; index < _optionGroups.length; index++)
                  _OptionGroupEditor(
                    key: ValueKey<int>(_optionGroupIds[index]),
                    group: _optionGroups[index],
                    onChanged: (ProductOptionGroup group) {
                      final List<ProductOptionGroup> groups =
                          List<ProductOptionGroup>.of(_optionGroups);
                      groups[index] = group;
                      setState(() => _optionGroups = groups);
                    },
                    onRemove: () => setState(() {
                      _optionGroups = List<ProductOptionGroup>.of(_optionGroups)
                        ..removeAt(index);
                      _optionGroupIds = List<int>.of(_optionGroupIds)
                        ..removeAt(index);
                    }),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to customers'),
                  subtitle: const Text('Turn off to hide it (e.g. sold out)'),
                  value: _isAvailable,
                  onChanged: (bool v) => setState(() => _isAvailable = v),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEditing ? 'Save changes' : 'Post product'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionGroupEditor extends StatefulWidget {
  const _OptionGroupEditor({
    super.key,
    required this.group,
    required this.onChanged,
    required this.onRemove,
  });

  final ProductOptionGroup group;
  final ValueChanged<ProductOptionGroup> onChanged;
  final VoidCallback onRemove;

  @override
  State<_OptionGroupEditor> createState() => _OptionGroupEditorState();
}

class _OptionGroupEditorState extends State<_OptionGroupEditor> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.group.name,
  );
  late final TextEditingController _choicesController = TextEditingController(
    text: widget.group.choices
        .map(
          (ProductOptionChoice choice) =>
              '${choice.label}${choice.priceAdjustment == 0 ? '' : '|${choice.priceAdjustment}'}',
        )
        .join('\n'),
  );
  late ProductOptionType _type = widget.group.type;
  late bool _required = widget.group.required;

  @override
  void dispose() {
    _nameController.dispose();
    _choicesController.dispose();
    super.dispose();
  }

  void _notify() {
    final List<ProductOptionChoice> choices = <ProductOptionChoice>[];
    if (_type != ProductOptionType.freeText) {
      for (final String line in _choicesController.text.split('\n')) {
        final String value = line.trim();
        if (value.isEmpty) continue;
        final List<String> parts = value.split('|');
        final String label = parts.first.trim();
        final double adjustment = parts.length > 1
            ? double.tryParse(parts[1].trim()) ?? double.nan
            : 0;
        choices.add(
          ProductOptionChoice(
            label: label,
            priceAdjustment: _type == ProductOptionType.tags ? 0 : adjustment,
          ),
        );
      }
    }
    widget.onChanged(
      ProductOptionGroup(
        name: _nameController.text.trim(),
        type: _type,
        required: _required,
        choices: choices,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Group name'),
                    onChanged: (_) => _notify(),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove option group',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            DropdownButtonFormField<ProductOptionType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Group type'),
              items: const <DropdownMenuItem<ProductOptionType>>[
                DropdownMenuItem(
                  value: ProductOptionType.singleChoice,
                  child: Text('Single choice'),
                ),
                DropdownMenuItem(
                  value: ProductOptionType.freeText,
                  child: Text('Free text'),
                ),
                DropdownMenuItem(
                  value: ProductOptionType.tags,
                  child: Text('Allergen tags'),
                ),
              ],
              onChanged: (ProductOptionType? type) {
                if (type == null) return;
                setState(() => _type = type);
                _notify();
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Customer must provide a value'),
              value: _required,
              onChanged: (bool required) {
                setState(() => _required = required);
                _notify();
              },
            ),
            if (_type != ProductOptionType.freeText)
              TextField(
                controller: _choicesController,
                decoration: InputDecoration(
                  labelText: _type == ProductOptionType.tags
                      ? 'Allergen tags'
                      : 'Choices',
                  helperText: _type == ProductOptionType.tags
                      ? 'One tag per line.'
                      : 'One choice per line; optional price adjustment as Label|amount.',
                ),
                maxLines: 4,
                onChanged: (_) => _notify(),
              ),
          ],
        ),
      ),
    );
  }
}
