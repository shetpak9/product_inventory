import 'package:flutter/material.dart';
import 'package:product_inventory/model/promotion.dart';
import 'package:product_inventory/service/database.dart';
import 'package:product_inventory/service/payment_service.dart';

class SellerPromotionsTab extends StatelessWidget {
  const SellerPromotionsTab({super.key, required this.sellerId});

  final String sellerId;

  @override
  Widget build(BuildContext context) {
    final DatabaseService database = DatabaseService();
    return StreamBuilder<List<Promotion>>(
      stream: database.promotionsStream(sellerId),
      builder: (BuildContext context, AsyncSnapshot<List<Promotion>> snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Unable to load promotions: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final List<Promotion> promotions = snapshot.data!;
        if (promotions.isEmpty) {
          return const Center(
            child: Text('No promotions yet. Add one to attract customers.'),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: promotions.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int index) {
            final Promotion promotion = promotions[index];
            final String discount = promotion.type == PromotionType.percentage
                ? '${promotion.value.toStringAsFixed(0)}% off'
                : '₱${promotion.value.toStringAsFixed(2)} off';
            return Card(
              child: ListTile(
                title: Text(promotion.code),
                subtitle: Text(
                  '$discount · minimum ₱${promotion.minOrderAmount.toStringAsFixed(2)}\n'
                  'Uses: ${promotion.usageCount}/${promotion.usageLimit?.toString() ?? 'unlimited'}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await database.deletePromotion(promotion);
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Could not delete promotion: $error'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class PromotionFormScreen extends StatefulWidget {
  const PromotionFormScreen({super.key, required this.sellerId});

  final String sellerId;

  @override
  State<PromotionFormScreen> createState() => _PromotionFormScreenState();
}

class _PromotionFormScreenState extends State<PromotionFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _code = TextEditingController();
  final TextEditingController _value = TextEditingController();
  final TextEditingController _minimum = TextEditingController(text: '0');
  final TextEditingController _limit = TextEditingController();
  PromotionType _type = PromotionType.percentage;
  DateTime _startsAt = DateTime.now();
  DateTime _endsAt = DateTime.now().add(const Duration(days: 30));
  bool _saving = false;

  @override
  void dispose() {
    _code.dispose();
    _value.dispose();
    _minimum.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_endsAt.isAfter(_startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Expiration date must be after the start date.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final String code = _code.text.trim().toUpperCase();
      await DatabaseService().savePromotion(
        Promotion(
          id: code,
          sellerId: widget.sellerId,
          code: code,
          type: _type,
          value: double.parse(_value.text.trim()),
          startsAt: _startsAt.millisecondsSinceEpoch,
          endsAt: _endsAt.millisecondsSinceEpoch,
          minOrderAmount: double.parse(_minimum.text.trim()),
          usageLimit: _limit.text.trim().isEmpty
              ? null
              : int.parse(_limit.text.trim()),
        ),
      );
      try {
        await PaymentService().publishPromotionNotifications(
          promotionId: code,
          code: code,
        );
      } catch (error) {
        debugPrint('Promotion saved, but notifications were not sent: $error');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save promotion: $error')),
      );
    }
  }

  String _dateLabel(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New promotion')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            TextFormField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Discount code'),
              validator: (String? value) {
                final String code = (value ?? '').trim();
                return RegExp(r'^[A-Za-z0-9_-]{3,30}$').hasMatch(code)
                    ? null
                    : 'Use 3–30 letters, numbers, _ or -';
              },
            ),
            DropdownButtonFormField<PromotionType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Discount type'),
              items: const <DropdownMenuItem<PromotionType>>[
                DropdownMenuItem(
                  value: PromotionType.percentage,
                  child: Text('Percentage'),
                ),
                DropdownMenuItem(
                  value: PromotionType.fixed,
                  child: Text('Fixed amount'),
                ),
              ],
              onChanged: (PromotionType? value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            TextFormField(
              controller: _value,
              decoration: const InputDecoration(labelText: 'Discount value'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (String? value) {
                final double? number = double.tryParse((value ?? '').trim());
                if (number == null ||
                    number <= 0 ||
                    (_type == PromotionType.percentage && number > 100)) {
                  return _type == PromotionType.percentage
                      ? 'Enter a percentage from 0.01 to 100'
                      : 'Enter an amount greater than 0';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _minimum,
              decoration: const InputDecoration(
                labelText: 'Minimum order amount',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (String? value) =>
                  double.tryParse((value ?? '').trim()) == null
                  ? 'Enter a valid amount'
                  : null,
            ),
            TextFormField(
              controller: _limit,
              decoration: const InputDecoration(
                labelText: 'Usage limit',
                hintText: 'Leave empty for unlimited',
              ),
              keyboardType: TextInputType.number,
              validator: (String? value) {
                if ((value ?? '').trim().isEmpty) return null;
                final int? limit = int.tryParse(value!.trim());
                return limit == null || limit < 1
                    ? 'Enter a positive whole number'
                    : null;
              },
            ),
            ListTile(
              title: Text('Starts: ${_dateLabel(_startsAt)}'),
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: _startsAt,
                );
                if (picked != null) setState(() => _startsAt = picked);
              },
            ),
            ListTile(
              title: Text('Expires: ${_dateLabel(_endsAt)}'),
              onTap: () async {
                final DateTime? picked = await showDatePicker(
                  context: context,
                  firstDate: _startsAt,
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                  initialDate: _endsAt,
                );
                if (picked != null) setState(() => _endsAt = picked);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : const Text('Save promotion'),
            ),
          ],
        ),
      ),
    );
  }
}
