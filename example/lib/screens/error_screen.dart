import 'package:flutter/material.dart';

import '../widgets/primary_button.dart';

enum ExampleErrorType {
  expired,
  cancelled,
  permissionDenied,
  initialization,
}

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
          title: 'Documento vencido',
          message:
              'El documento escaneado tiene una fecha de caducidad expirada. '
              'Intente con un documento de identidad vigente.',
        );
      case ExampleErrorType.cancelled:
        return _ErrorContent(
          icon: Icons.close_outlined,
          color: colors.outline,
          title: 'Captura cancelada',
          message: 'El escaneo se interrumpió antes de finalizar.',
        );
      case ExampleErrorType.permissionDenied:
        return _ErrorContent(
          icon: Icons.no_photography_outlined,
          color: colors.error,
          title: 'Permiso de cámara denegado',
          message:
              'Active el acceso a la cámara desde la configuración del '
              'dispositivo para continuar.',
        );
      case ExampleErrorType.initialization:
        return _ErrorContent(
          icon: Icons.error_outline,
          color: colors.error,
          title: 'No se pudo iniciar la cámara',
          message:
              'Ocurrió un problema al iniciar la cámara. Verifique que no '
              'esté siendo usada por otra aplicación e intente nuevamente.',
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
                  label: 'Reintentar',
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
