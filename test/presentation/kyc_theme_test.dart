import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KycTheme.defaults — sane defaults', () {
    final theme = KycTheme.defaults();

    test('primary is the InClub blue (#19809E)', () {
      expect(theme.primary, equals(const Color(0xFF19809E)));
    });

    test('success is green (#16A34A)', () {
      expect(theme.success, equals(const Color(0xFF16A34A)));
    });

    test('error is red (#E01E37)', () {
      expect(theme.error, equals(const Color(0xFFE01E37)));
    });

    test('white is Colors.white', () {
      expect(theme.white, equals(Colors.white));
    });

    test('white60 is 60% opaque white', () {
      expect(theme.white60, equals(const Color(0x99FFFFFF)));
    });

    test('white70 is 70% opaque white', () {
      expect(theme.white70, equals(const Color(0xB3FFFFFF)));
    });

    test('overlayDark is ~65% black', () {
      expect(theme.overlayDark, equals(const Color(0xA6000000)));
    });

    test('overlayMedium is ~54% black', () {
      expect(theme.overlayMedium, equals(const Color(0x8A000000)));
    });

    test('shadowCard is 4% black', () {
      expect(theme.shadowCard, equals(const Color(0x0A000000)));
    });
  });

  group('KycTheme.darkDefaults — sane dark values', () {
    final theme = KycTheme.darkDefaults();

    test('primary differs from light defaults', () {
      expect(theme.primary, isNot(equals(KycTheme.defaults().primary)));
    });

    test('textPrimary is light (high contrast on dark background)', () {
      expect(theme.textPrimary, equals(const Color(0xFFEDEDED)));
    });

    test('overlayDark is darker than light variant', () {
      expect(theme.overlayDark, equals(const Color(0xCC000000)));
    });
  });

  group('KycTheme.fromMaterialTheme — maps Material 3 ColorScheme', () {
    testWidgets('reads primary, error, surface from ColorScheme', (
      tester,
    ) async {
      final material = ThemeData(
        colorSchemeSeed: const Color(0xFF00838F),
        useMaterial3: true,
      );
      final theme = KycTheme.fromMaterialTheme(material);

      expect(theme.primary, equals(material.colorScheme.primary));
      expect(theme.error, equals(material.colorScheme.error));
      expect(theme.textPrimary, equals(material.colorScheme.onSurface));
    });
  });

  group('KycTheme.copyWith — partial override', () {
    test('only changes the specified fields', () {
      final base = KycTheme.defaults();
      final overridden = base.copyWith(primary: const Color(0xFF000000));

      expect(overridden.primary, equals(const Color(0xFF000000)));
      expect(overridden.success, equals(base.success));
      expect(overridden.white, equals(base.white));
    });

    test('no overrides returns equivalent theme', () {
      final base = KycTheme.defaults();
      expect(base.copyWith(), equals(base));
    });
  });

  group('KycTheme.defaults — gradient tokens', () {
    final theme = KycTheme.defaults();

    test('gradientStart is green (#00C853)', () {
      expect(theme.gradientStart, equals(const Color(0xFF00C853)));
    });

    test('gradientEnd is teal (#1DE9B6)', () {
      expect(theme.gradientEnd, equals(const Color(0xFF1DE9B6)));
    });
  });

  group('KycTheme.darkDefaults — gradient tokens', () {
    final theme = KycTheme.darkDefaults();

    test('gradientStart dark is green (#22C55E)', () {
      expect(theme.gradientStart, equals(const Color(0xFF22C55E)));
    });

    test('gradientEnd dark is teal (#34D399)', () {
      expect(theme.gradientEnd, equals(const Color(0xFF34D399)));
    });
  });

  group('KycTheme.fromMaterialTheme — gradient tokens', () {
    testWidgets('gradientStart maps to scheme.primary', (tester) async {
      final material = ThemeData(
        colorSchemeSeed: const Color(0xFF00838F),
        useMaterial3: true,
      );
      final theme = KycTheme.fromMaterialTheme(material);
      expect(theme.gradientStart, equals(material.colorScheme.primary));
    });

    testWidgets('gradientEnd maps to scheme.tertiary', (tester) async {
      final material = ThemeData(
        colorSchemeSeed: const Color(0xFF00838F),
        useMaterial3: true,
      );
      final theme = KycTheme.fromMaterialTheme(material);
      expect(theme.gradientEnd, equals(material.colorScheme.tertiary));
    });
  });

  group('KycTheme.copyWith — gradient tokens', () {
    test('copyWith replaces gradientStart only', () {
      final base = KycTheme.defaults();
      final updated = base.copyWith(gradientStart: const Color(0xFFAABBCC));
      expect(updated.gradientStart, equals(const Color(0xFFAABBCC)));
      expect(updated.gradientEnd, equals(base.gradientEnd));
    });

    test('copyWith replaces gradientEnd only', () {
      final base = KycTheme.defaults();
      final updated = base.copyWith(gradientEnd: const Color(0xFFDDEEFF));
      expect(updated.gradientEnd, equals(const Color(0xFFDDEEFF)));
      expect(updated.gradientStart, equals(base.gradientStart));
    });

    test('no overrides preserves gradient tokens', () {
      final base = KycTheme.defaults();
      expect(base.copyWith().gradientStart, equals(base.gradientStart));
      expect(base.copyWith().gradientEnd, equals(base.gradientEnd));
    });
  });

  group('KycTheme — value equality and hashCode', () {
    test('two defaults() are equal', () {
      expect(KycTheme.defaults(), equals(KycTheme.defaults()));
      expect(
          KycTheme.defaults().hashCode, equals(KycTheme.defaults().hashCode));
    });

    test('themes differing in one color are not equal', () {
      final a = KycTheme.defaults();
      const b = KycTheme(
        primary: Color(0xFF000000),
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
      expect(a, isNot(equals(b)));
    });

    test('themes differing in gradientStart are not equal', () {
      final a = KycTheme.defaults();
      final b = a.copyWith(gradientStart: const Color(0xFF000000));
      expect(a, isNot(equals(b)));
    });

    test('themes differing in gradientEnd are not equal', () {
      final a = KycTheme.defaults();
      final b = a.copyWith(gradientEnd: const Color(0xFF000000));
      expect(a, isNot(equals(b)));
    });
  });

  group('KycThemeProvider — InheritedWidget lookup', () {
    testWidgets('KycTheme.of(context) returns the provided theme', (
      tester,
    ) async {
      const customTheme = KycTheme(
        primary: Color(0xFF111111),
        primarySolid: Color(0xFF222222),
        accentOrange: Color(0xFF333333),
        success: Color(0xFF444444),
        warningIcon: Color(0xFF555555),
        error: Color(0xFF666666),
        errorLight: Color(0xFF777777),
        errorBorder: Color(0xFF888888),
        textPrimary: Color(0xFF999999),
        textTertiary: Color(0xFFAAAAAA),
        border: Color(0xFFBBBBBB),
        backgroundFieldAlt: Color(0xFFCCCCCC),
        backgroundGrey: Color(0xFFDDDDDD),
        shadowCard: Color(0xFFEEEEEE),
        overlayDark: Color(0xFFFFFFFE),
        overlayMedium: Color(0xFFFFFFFD),
        white: Color(0xFFFFFFFC),
        white60: Color(0xFFFFFFFB),
        white70: Color(0xFFFFFFFA),
        gradientStart: Color(0xFF001122),
        gradientEnd: Color(0xFF334455),
      );

      late KycTheme captured;
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: customTheme,
            child: Builder(
              builder: (context) {
                captured = KycTheme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(captured, equals(customTheme));
      expect(captured.primary, equals(const Color(0xFF111111)));
    });

    testWidgets(
      'KycTheme.of(context) falls back to defaults when no provider is present',
      (tester) async {
        KycTheme? captured;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                captured = KycTheme.of(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        );

        expect(captured, isNotNull);
        expect(captured, equals(KycTheme.defaults()));
      },
    );
  });
}
