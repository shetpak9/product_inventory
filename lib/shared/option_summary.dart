import 'package:flutter/material.dart';

class OptionSummary extends StatelessWidget {
  const OptionSummary({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        options.entries
            .map((MapEntry<String, Object?> entry) {
              final Object? value = entry.value;
              final String text = value is List
                  ? value.map((Object? item) => item.toString()).join(', ')
                  : value.toString();
              return '${entry.key}: $text';
            })
            .join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
