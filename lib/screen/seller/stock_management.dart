import 'package:flutter/material.dart';
import 'package:product_inventory/model/product.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/shared/product_thumb.dart';

enum StockStatus { inStock, lowStock, outOfStock, notTracked }

StockStatus stockStatus(Product product) {
  final int? quantity = product.stockQuantity;
  if (quantity == null) return StockStatus.notTracked;
  if (quantity == 0) return StockStatus.outOfStock;
  if (quantity <= 5) return StockStatus.lowStock;
  return StockStatus.inStock;
}

String stockStatusLabel(Product product) {
  switch (stockStatus(product)) {
    case StockStatus.inStock:
      return 'In Stock';
    case StockStatus.lowStock:
      return 'Low Stock';
    case StockStatus.outOfStock:
      return 'Out of Stock';
    case StockStatus.notTracked:
      return 'Not Tracked';
  }
}

Color stockStatusColor(BuildContext context, Product product) {
  switch (stockStatus(product)) {
    case StockStatus.inStock:
      return Colors.green.shade700;
    case StockStatus.lowStock:
      return Colors.orange.shade800;
    case StockStatus.outOfStock:
      return Theme.of(context).colorScheme.error;
    case StockStatus.notTracked:
      return Theme.of(context).colorScheme.outline;
  }
}

Future<bool?> showStockManagementDialog(BuildContext context, Product product) {
  return showDialog<bool>(
    context: context,
    builder: (_) => StockManagementDialog(product: product),
  );
}

class StockManagementDialog extends StatefulWidget {
  const StockManagementDialog({super.key, required this.product});

  final Product product;

  @override
  State<StockManagementDialog> createState() => _StockManagementDialogState();
}

class _StockManagementDialogState extends State<StockManagementDialog> {
  final DatabaseService _database = DatabaseService();
  late final TextEditingController _controller = TextEditingController(
    text: widget.product.stockQuantity?.toString() ?? '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final int quantity = int.parse(_controller.text.trim());
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _database.updateStockQuantity(widget.product.id, quantity);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint('Stock update failed: $error');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not update stock. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color statusColor = stockStatusColor(context, widget.product);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          ProductThumb(url: widget.product.imageUrl, size: 44),
          const SizedBox(width: 12),
          Expanded(child: Text(widget.product.name)),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Current stock: ${widget.product.stockQuantity?.toString() ?? 'Not Tracked'}',
            ),
            const SizedBox(height: 4),
            Text(
              stockStatusLabel(widget.product),
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              autofocus: true,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'New stock quantity',
                helperText: 'Enter 0 to mark this product out of stock.',
              ),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                final int? quantity = int.tryParse(text);
                if (quantity == null || !RegExp(r'^\d+$').hasMatch(text)) {
                  return 'Enter a whole number.';
                }
                if (quantity > 1000000) {
                  return 'Maximum stock is 1,000,000.';
                }
                return null;
              },
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
