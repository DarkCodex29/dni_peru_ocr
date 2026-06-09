import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    debugPrint('No .env file found — APISPERU_TOKEN unavailable');
  }
  DniLogger.enable();
  runApp(const DniPeruOcrExampleApp());
}

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
