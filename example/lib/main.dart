import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

void main() {
  runApp(const DniPeruOcrExampleApp());
}

/// Root widget of the example app.
///
/// PR #22 wires only a placeholder home screen. PR #23 replaces it with the
/// real [HomeScreen].
class DniPeruOcrExampleApp extends StatelessWidget {
  const DniPeruOcrExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'dni_peru_ocr example',
      theme: AppTheme.light(),
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('dni_peru_ocr example')),
      body: const Center(
        child: Text(
          'Example app scaffolded.\nHome screen arrives in the next PR.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
