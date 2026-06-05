import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as imglib;
import 'package:dni_peru_ocr/src/presentation/image_quality_gate.dart';
import 'package:mocktail/mocktail.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

/// Mockable wrapper around LivenessAnalyzer interface
class MockLivenessAnalyzer extends Mock implements LivenessAnalyzer {}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Encodes a plain 10×10 white [imglib.Image] to PNG bytes.
/// This is a valid image that [imglib.decodeImage] can decode.
Uint8List _validImageBytes() {
  final img = imglib.Image(width: 10, height: 10);
  imglib.fill(img, color: imglib.ColorRgb8(255, 255, 255));
  return Uint8List.fromList(imglib.encodePng(img));
}

/// Returns an empty/invalid byte sequence that [imglib.decodeImage] will reject.
Uint8List _invalidImageBytes() => Uint8List.fromList([0x00, 0x01, 0x02]);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late MockLivenessAnalyzer mockAnalyzer;
  late ImageQualityGate gate;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockAnalyzer = MockLivenessAnalyzer();
    gate = ImageQualityGate(analyzer: mockAnalyzer);
  });

  // ── checkBlur ─────────────────────────────────────────────────────────────

  group('isBlurry', () {
    test(
      'returns true (blurry) when laplacian score is below threshold',
      () async {
        // Laplacian score of 10 < default threshold (100) → blurry
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: true,
            laplacianScore: 10.0,
          ),
        );

        final result = await gate.isBlurry(_validImageBytes());

        expect(result, isTrue);
      },
    );

    test(
      'returns false (sharp) when laplacian score is above threshold',
      () async {
        // Laplacian score of 5000 > default threshold (100) → sharp
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: true,
            laplacianScore: 5000.0,
          ),
        );

        final result = await gate.isBlurry(_validImageBytes());

        expect(result, isFalse);
      },
    );

    test(
      'boundary: laplacian exactly at threshold is NOT blurry (>= passes)',
      () async {
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: true,
            laplacianScore: 100.0, // exactly at default threshold
          ),
        );

        final result = await gate.isBlurry(_validImageBytes());

        // 100 >= 100 → sharp
        expect(result, isFalse);
      },
    );

    test(
      'throws ImageQualityException when image bytes cannot be decoded',
      () async {
        await expectLater(
          () => gate.isBlurry(_invalidImageBytes()),
          throwsA(isA<ImageQualityException>()),
        );

        // analyzer should NOT have been called when decode fails
        verifyNever(() => mockAnalyzer.analyze(any()));
      },
    );
  });

  // ── isReal (liveness) ────────────────────────────────────────────────────

  group('isReal', () {
    test('returns true (real) when liveness result is live', () async {
      when(() => mockAnalyzer.analyze(any())).thenAnswer(
        (_) async => const LivenessResult(
          isLive: true,
          laplacianScore: 5000.0,
        ),
      );

      final result = await gate.isReal(_validImageBytes());

      expect(result, isTrue);
    });

    test('returns false (fake) when liveness result is not live', () async {
      when(() => mockAnalyzer.analyze(any())).thenAnswer(
        (_) async => const LivenessResult(
          isLive: false,
          laplacianScore: 5000.0,
        ),
      );

      final result = await gate.isReal(_validImageBytes());

      expect(result, isFalse);
    });

    test(
      'throws ImageQualityException when image bytes cannot be decoded',
      () async {
        await expectLater(
          () => gate.isReal(_invalidImageBytes()),
          throwsA(isA<ImageQualityException>()),
        );

        verifyNever(() => mockAnalyzer.analyze(any()));
      },
    );
  });

  // ── validate ────────────────────────────────────────────────────────────

  group('validate', () {
    test(
      'returns QualityCheckResult.pass when image is sharp and real',
      () async {
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: true,
            laplacianScore: 5000.0,
          ),
        );

        final result = await gate.validate(_validImageBytes());

        expect(result, QualityCheckResult.pass);
      },
    );

    test(
      'returns QualityCheckResult.blurry when laplacian is below threshold',
      () async {
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: true,
            laplacianScore: 50.0, // blurry (below threshold of 100)
          ),
        );

        final result = await gate.validate(_validImageBytes());

        expect(result, QualityCheckResult.blurry);
      },
    );

    test('returns QualityCheckResult.spoofed when liveness fails', () async {
      when(() => mockAnalyzer.analyze(any())).thenAnswer(
        (_) async => const LivenessResult(
          isLive: false,
          laplacianScore: 5000.0,
        ),
      );

      final result = await gate.validate(_validImageBytes());

      expect(result, QualityCheckResult.spoofed);
    });

    test(
      'checks blur BEFORE liveness (fail fast — only one analyze call)',
      () async {
        // Blurry AND spoofed → should return blurry without checking liveness separately.
        // Under the hood, a single analyze() call provides both laplacianScore + isLive.
        // When laplacianScore < threshold, gate returns blurry immediately.
        // Our gate must return QualityCheckResult.blurry (not spoofed).
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: false, // liveness also false but blur wins
            laplacianScore: 10.0, // blurry
          ),
        );

        final result = await gate.validate(_validImageBytes());

        // Blur wins — reported as blurry, not spoofed
        expect(result, QualityCheckResult.blurry);
        // Only one analyze call (not two separate calls)
        verify(() => mockAnalyzer.analyze(any())).called(1);
      },
    );

    test(
      'returns QualityCheckResult.error when image cannot be decoded',
      () async {
        final result = await gate.validate(_invalidImageBytes());

        expect(result, QualityCheckResult.error);
        verifyNever(() => mockAnalyzer.analyze(any()));
      },
    );
  });

  // ── ImageQualityResult fields ─────────────────────────────────────────────

  group('analyze (full result)', () {
    test(
      'returns correct ImageQualityResult with all fields populated',
      () async {
        when(() => mockAnalyzer.analyze(any())).thenAnswer(
          (_) async => const LivenessResult(
            isLive: true,
            laplacianScore: 4500.0,
          ),
        );

        final result = await gate.analyze(_validImageBytes());

        expect(result.isLive, isTrue);
        expect(result.isSharp, isTrue);
        expect(result.laplacianScore, closeTo(4500.0, 1.0));
      },
    );

    test('isSharp is false when laplacian below threshold', () async {
      when(() => mockAnalyzer.analyze(any())).thenAnswer(
        (_) async => const LivenessResult(
          isLive: false,
          laplacianScore: 50.0, // below threshold
        ),
      );

      final result = await gate.analyze(_validImageBytes());

      expect(result.isSharp, isFalse);
      expect(result.isLive, isFalse);
      expect(result.laplacianScore, closeTo(50.0, 1.0));
    });
  });
}
