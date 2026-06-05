import 'package:flutter/material.dart';

/// Theming abstraction for the KYC scanner widgets.
///
/// Decouples the camera mask, scanner steps and validators from the host
/// application's color constants. The host app passes a [KycTheme] (or relies
/// on [KycTheme.defaults]) and every internal widget reads colors from this
/// object instead of importing host-specific color palettes.
@immutable
class KycTheme {
  const KycTheme({
    required this.primary,
    required this.primarySolid,
    required this.accentOrange,
    required this.success,
    required this.warningIcon,
    required this.error,
    required this.errorLight,
    required this.errorBorder,
    required this.textPrimary,
    required this.textTertiary,
    required this.border,
    required this.backgroundFieldAlt,
    required this.backgroundGrey,
    required this.shadowCard,
    required this.overlayDark,
    required this.overlayMedium,
    required this.white,
    required this.white60,
    required this.white70,
  });

  /// Default theme using neutral, brand-agnostic values. Consumers should
  /// override colors that need to match their app's palette.
  factory KycTheme.defaults() => const KycTheme(
    primary: Color(0xFF19809E),
    primarySolid: Color(0xFF0B3A47),
    accentOrange: Color(0xFFFE7C04),
    success: Color(0xFF16A34A),
    warningIcon: Color(0xFFFF9800),
    error: Color(0xFFE01E37),
    errorLight: Color(0xFFFEE2E2),
    errorBorder: Color(0xFFE01E37),
    textPrimary: Color(0xFF212121),
    textTertiary: Color(0xFF5F7081),
    border: Color(0xFFE0E0E0),
    backgroundFieldAlt: Color(0xFFF8F9FA),
    backgroundGrey: Color(0xFFEDEDED),
    shadowCard: Color(0x0A000000),
    overlayDark: Color(0xA6000000),
    overlayMedium: Color(0x8A000000),
    white: Colors.white,
    white60: Color(0x99FFFFFF),
    white70: Color(0xB3FFFFFF),
  );

  // Brand
  final Color primary;
  final Color primarySolid;
  final Color accentOrange;

  // Status
  final Color success;
  final Color warningIcon;
  final Color error;
  final Color errorLight;
  final Color errorBorder;

  // Text
  final Color textPrimary;
  final Color textTertiary;

  // Surfaces
  final Color border;
  final Color backgroundFieldAlt;
  final Color backgroundGrey;
  final Color shadowCard;

  // Camera overlay
  final Color overlayDark;
  final Color overlayMedium;
  final Color white;
  final Color white60;
  final Color white70;

  /// Reads the nearest [KycTheme] in the widget tree.
  ///
  /// Throws when no [KycThemeProvider] is present.
  static KycTheme of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<KycThemeProvider>();
    if (provider == null) {
      throw FlutterError(
        'KycTheme.of() called with a context that does not contain a '
        'KycThemeProvider. Wrap your widget tree with KycThemeProvider.',
      );
    }
    return provider.theme;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KycTheme &&
        other.primary == primary &&
        other.primarySolid == primarySolid &&
        other.accentOrange == accentOrange &&
        other.success == success &&
        other.warningIcon == warningIcon &&
        other.error == error &&
        other.errorLight == errorLight &&
        other.errorBorder == errorBorder &&
        other.textPrimary == textPrimary &&
        other.textTertiary == textTertiary &&
        other.border == border &&
        other.backgroundFieldAlt == backgroundFieldAlt &&
        other.backgroundGrey == backgroundGrey &&
        other.shadowCard == shadowCard &&
        other.overlayDark == overlayDark &&
        other.overlayMedium == overlayMedium &&
        other.white == white &&
        other.white60 == white60 &&
        other.white70 == white70;
  }

  @override
  int get hashCode => Object.hashAll(_hashFields);

  List<Object?> get _hashFields => [
    primary,
    primarySolid,
    accentOrange,
    success,
    warningIcon,
    error,
    errorLight,
    errorBorder,
    textPrimary,
    textTertiary,
    border,
    backgroundFieldAlt,
    backgroundGrey,
    shadowCard,
    overlayDark,
    overlayMedium,
    white,
    white60,
    white70,
  ];
}

/// Injects a [KycTheme] into the widget tree for descendants to read via
/// [KycTheme.of].
class KycThemeProvider extends InheritedWidget {
  const KycThemeProvider({
    required this.theme,
    required super.child,
    super.key,
  });

  final KycTheme theme;

  @override
  bool updateShouldNotify(KycThemeProvider oldWidget) {
    return theme != oldWidget.theme;
  }
}
