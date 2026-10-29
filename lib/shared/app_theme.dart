import 'package:flutter/material.dart';

/// Shown in every app bar. Change this to your bakery's name.
const String kShopName = "Alas Pandesal";

/// Shown on the checkout screen.
const String kShippingNote = 'Free shipping · Delivery within 48 hours';

/// Tax added at checkout (0.12 = 12%). Keep at 0 to hide the tax line.
const double kTaxRate = 0.0;

class AppColors {
  const AppColors._();

  static const Color background = Color(0xFFFDF8F0);
  static const Color appBar = Color(0xFFD7CCC8);
  static const Color placeholder = Color(0xFFEFE6DA);
  static const Color accent = Colors.pink;
}

String formatPeso(double amount) => '₱${amount.toStringAsFixed(2)}';

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.appBar,
      foregroundColor: Colors.black,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
    ),
  );
}
