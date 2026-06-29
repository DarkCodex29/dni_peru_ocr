import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/domain/entities/validation_gate.dart';
import 'package:dni_peru_ocr/src/presentation/lighting_gate.dart';

List<int> _uniformLuminance(int value, {int count = 400}) =>
    List<int>.filled(count, value);

List<int> _withSaturatedFraction(double fraction, {int count = 1000}) {
  final saturated = (count * fraction).round();
  return List<int>.generate(
    count,
    (i) => i < saturated ? 255 : 120,
  );
}

void main() {
  group('LightingGate.evaluate — luminance band', () {
    test('dark buffer below minLuminance is invalid', () {
      final result = LightingGate.evaluate(_uniformLuminance(20));

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.lighting);
      expect(result.meanLuminance, closeTo(20, 0.001));
    });

    test('bright-normal buffer within band is valid', () {
      final result = LightingGate.evaluate(_uniformLuminance(140));

      expect(result.isValid, isTrue);
      expect(result.failing, isNull);
      expect(result.meanLuminance, closeTo(140, 0.001));
      expect(result.saturatedFraction, closeTo(0, 0.001));
    });

    test('over-bright buffer above maxLuminance is invalid', () {
      final result = LightingGate.evaluate(_uniformLuminance(245));

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.lighting);
    });

    test('mean exactly at minLuminance threshold is valid', () {
      final result = LightingGate.evaluate(
        _uniformLuminance(LightingGate.minLuminance.toInt()),
      );

      expect(result.isValid, isTrue);
      expect(result.failing, isNull);
    });

    test('mean just below minLuminance threshold is invalid', () {
      final result = LightingGate.evaluate(
        _uniformLuminance(LightingGate.minLuminance.toInt() - 1),
      );

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.lighting);
    });

    test('mean exactly at maxLuminance threshold is valid', () {
      final result = LightingGate.evaluate(
        _uniformLuminance(LightingGate.maxLuminance.toInt()),
      );

      expect(result.isValid, isTrue);
      expect(result.failing, isNull);
    });
  });

  group('LightingGate.evaluate — glare via saturated fraction', () {
    test('glare buffer above maxSaturatedFraction is invalid', () {
      final result = LightingGate.evaluate(_withSaturatedFraction(0.25));

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.glare);
      expect(
        result.saturatedFraction,
        greaterThan(LightingGate.maxSaturatedFraction),
      );
    });

    test('saturated fraction just below threshold is valid', () {
      final result = LightingGate.evaluate(_withSaturatedFraction(0.09));

      expect(result.isValid, isTrue);
      expect(result.failing, isNull);
    });

    test('saturated fraction exactly at threshold is valid', () {
      final result = LightingGate.evaluate(_withSaturatedFraction(0.10));

      expect(result.isValid, isTrue);
      expect(result.failing, isNull);
    });
  });

  group('LightingGate.evaluate — degenerate input', () {
    test('empty buffer is invalid lighting', () {
      final result = LightingGate.evaluate(const <int>[]);

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.lighting);
    });
  });
}
