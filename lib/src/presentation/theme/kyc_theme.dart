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
    required this.gradientStart,
    required this.gradientEnd,
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
        gradientStart: Color(0xFF00C853),
        gradientEnd: Color(0xFF1DE9B6),
      );

  /// Dark variant of the default theme. Tuned for OLED displays — uses
  /// near-black surfaces and brighter accents to preserve contrast.
  factory KycTheme.darkDefaults() => const KycTheme(
        primary: Color(0xFF2EAFD4),
        primarySolid: Color(0xFF052631),
        accentOrange: Color(0xFFFF8A1F),
        success: Color(0xFF22C55E),
        warningIcon: Color(0xFFFFB020),
        error: Color(0xFFFF4D6D),
        errorLight: Color(0xFF2A0E14),
        errorBorder: Color(0xFFFF4D6D),
        textPrimary: Color(0xFFEDEDED),
        textTertiary: Color(0xFFA0AEC0),
        border: Color(0xFF2A2A2A),
        backgroundFieldAlt: Color(0xFF101012),
        backgroundGrey: Color(0xFF1A1A1C),
        shadowCard: Color(0x33000000),
        overlayDark: Color(0xCC000000),
        overlayMedium: Color(0xA6000000),
        white: Colors.white,
        white60: Color(0x99FFFFFF),
        white70: Color(0xB3FFFFFF),
        gradientStart: Color(0xFF22C55E),
        gradientEnd: Color(0xFF34D399),
      );

  /// Derives a [KycTheme] from a Material 3 [ThemeData], mapping Material
  /// semantic roles onto the KYC color slots. Useful when the host app
  /// already drives styling from Material 3 instead of bespoke palettes.
  factory KycTheme.fromMaterialTheme(ThemeData material) {
    final scheme = material.colorScheme;
    return KycTheme(
      primary: scheme.primary,
      primarySolid: scheme.primaryContainer,
      accentOrange: scheme.tertiary,
      success: const Color(0xFF16A34A),
      warningIcon: const Color(0xFFFF9800),
      error: scheme.error,
      errorLight: scheme.errorContainer,
      errorBorder: scheme.error,
      textPrimary: scheme.onSurface,
      textTertiary: scheme.onSurfaceVariant,
      border: scheme.outline,
      backgroundFieldAlt: scheme.surfaceContainerHighest,
      backgroundGrey: scheme.surfaceContainerHigh,
      shadowCard: const Color(0x0A000000),
      overlayDark: const Color(0xA6000000),
      overlayMedium: const Color(0x8A000000),
      white: Colors.white,
      white60: const Color(0x99FFFFFF),
      white70: const Color(0xB3FFFFFF),
      gradientStart: scheme.primary,
      gradientEnd: scheme.tertiary,
    );
  }

  /// Returns a copy of this theme with the given fields replaced.
  /// Useful for one-off color overrides without redefining the whole theme.
  KycTheme copyWith({
    Color? primary,
    Color? primarySolid,
    Color? accentOrange,
    Color? success,
    Color? warningIcon,
    Color? error,
    Color? errorLight,
    Color? errorBorder,
    Color? textPrimary,
    Color? textTertiary,
    Color? border,
    Color? backgroundFieldAlt,
    Color? backgroundGrey,
    Color? shadowCard,
    Color? overlayDark,
    Color? overlayMedium,
    Color? white,
    Color? white60,
    Color? white70,
    Color? gradientStart,
    Color? gradientEnd,
  }) {
    return KycTheme(
      primary: primary ?? this.primary,
      primarySolid: primarySolid ?? this.primarySolid,
      accentOrange: accentOrange ?? this.accentOrange,
      success: success ?? this.success,
      warningIcon: warningIcon ?? this.warningIcon,
      error: error ?? this.error,
      errorLight: errorLight ?? this.errorLight,
      errorBorder: errorBorder ?? this.errorBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textTertiary: textTertiary ?? this.textTertiary,
      border: border ?? this.border,
      backgroundFieldAlt: backgroundFieldAlt ?? this.backgroundFieldAlt,
      backgroundGrey: backgroundGrey ?? this.backgroundGrey,
      shadowCard: shadowCard ?? this.shadowCard,
      overlayDark: overlayDark ?? this.overlayDark,
      overlayMedium: overlayMedium ?? this.overlayMedium,
      white: white ?? this.white,
      white60: white60 ?? this.white60,
      white70: white70 ?? this.white70,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
    );
  }

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

  // Banner gradient
  final Color gradientStart;
  final Color gradientEnd;

  static KycTheme of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<KycThemeProvider>();
    return provider?.theme ?? KycTheme.defaults();
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
        other.white70 == white70 &&
        other.gradientStart == gradientStart &&
        other.gradientEnd == gradientEnd;
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
        gradientStart,
        gradientEnd,
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
