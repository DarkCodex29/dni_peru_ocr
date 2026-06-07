import 'package:flutter/material.dart';

/// Placeholder shown until the real [ScanScreen] arrives in the next chained PR.
class ScanScreenPlaceholder extends StatelessWidget {
  const ScanScreenPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The capture flow lands in the next chained PR.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
