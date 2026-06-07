import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const DniPeruOcrExampleApp());
}

/// Root widget of the example app.
class DniPeruOcrExampleApp extends StatelessWidget {
  const DniPeruOcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dni_peru_ocr example',
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
