import 'package:flutter/material.dart';

/// Material 3 theme for the dni_peru_ocr example app.
///
/// Uses [ColorScheme.fromSeed] with an indigo seed for a calm, professional look.
/// Text theme inherits the Flutter defaults and only enlarges the headlines so
/// the demo's CTAs feel intentional without overriding readable defaults.
class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: Colors.indigo,
      brightness: Brightness.light,
    );
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontWeight: FontWeight.w700),
        headlineMedium: TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}
