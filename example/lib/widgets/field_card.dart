import 'package:flutter/material.dart';

import 'confidence_badge.dart';

/// Displays a single OCR field with its label, value, and confidence badge.
///
/// When the value is `null` (the library has not locked the field yet) the
/// card renders a muted placeholder so the reader still sees the slot.
class FieldCard extends StatelessWidget {
  const FieldCard({
    super.key,
    required this.label,
    required this.value,
    required this.confidence,
  });

  final String label;
  final String? value;
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null && value!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasValue ? value! : 'Not detected',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontStyle:
                          hasValue ? FontStyle.normal : FontStyle.italic,
                      color: hasValue
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (hasValue) ConfidenceBadge(confidence: confidence),
          ],
        ),
      ),
    );
  }
}
