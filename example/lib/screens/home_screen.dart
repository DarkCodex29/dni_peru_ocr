import 'package:flutter/material.dart';

import '../widgets/primary_button.dart';
import 'scan_screen_placeholder.dart';

/// Entry screen of the example app.
///
/// Explains the demo's purpose and exposes a single call-to-action that
/// drives the user into the capture flow.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String _libraryName = 'dni_peru_ocr';
  static const String _libraryVersion = '0.7.2';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Example'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _libraryName,
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'v$_libraryVersion',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'This demo walks through capturing both sides of a Peruvian '
                'DNI, demonstrates the front-to-back field seeding pattern, '
                'and displays the consensus result with per-field confidence.',
                style: theme.textTheme.bodyLarge,
              ),
              const Spacer(),
              Center(
                child: PrimaryButton(
                  label: 'Start scan',
                  icon: Icons.camera_alt_outlined,
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ScanScreenPlaceholder(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'A physical device is required.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
