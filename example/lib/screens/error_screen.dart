import 'package:flutter/material.dart';

import '../widgets/primary_button.dart';

/// Failure cases the example surfaces back to the user.
enum ExampleErrorType {
  expired,
  cancelled,
  permissionDenied,
  initialization,
}

/// Friendly error screen reused for every failure path in the capture flow.
///
/// Each [ExampleErrorType] maps to an icon, headline, and supporting copy so
/// that consumers see a clear reason and a single recovery action.
class ErrorScreen extends StatelessWidget {
  const ErrorScreen({
    super.key,
    required this.type,
  });

  final ExampleErrorType type;

  _ErrorContent _contentFor(ColorScheme colors) {
    switch (type) {
      case ExampleErrorType.expired:
        return _ErrorContent(
          icon: Icons.event_busy_outlined,
          color: colors.error,
          title: 'Document expired',
          message:
              'The document scanned has an expired date. Please try again '
              'with a valid identity document.',
        );
      case ExampleErrorType.cancelled:
        return _ErrorContent(
          icon: Icons.close_outlined,
          color: colors.outline,
          title: 'Capture cancelled',
          message: 'You left the camera before finishing the scan.',
        );
      case ExampleErrorType.permissionDenied:
        return _ErrorContent(
          icon: Icons.no_photography_outlined,
          color: colors.error,
          title: 'Camera permission denied',
          message:
              'Grant camera access in your device settings to use the scan '
              'flow.',
        );
      case ExampleErrorType.initialization:
        return _ErrorContent(
          icon: Icons.error_outline,
          color: colors.error,
          title: 'Could not start the camera',
          message:
              'Something went wrong while initializing the camera. Make sure '
              'no other app is using it and try again.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _contentFor(theme.colorScheme);

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(content.icon, size: 72, color: content.color),
              const SizedBox(height: 16),
              Text(
                content.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                content.message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const Spacer(),
              Center(
                child: PrimaryButton(
                  label: 'Try again',
                  icon: Icons.refresh,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorContent {
  const _ErrorContent({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
}
