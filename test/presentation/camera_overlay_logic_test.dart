import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('CameraOverlayTuning — invariants', () {
    test('autoCaptureMs is the canonical 1.5s countdown', () {
      expect(CameraOverlayTuning.autoCaptureMs, 1500);
    });

    test('gracePeriodMs is shorter than autoCaptureMs', () {
      expect(
        CameraOverlayTuning.gracePeriodMs,
        lessThan(CameraOverlayTuning.autoCaptureMs),
      );
    });

    test('eye thresholds are sane (closed < open)', () {
      expect(
        CameraOverlayTuning.eyeClosedThreshold,
        lessThan(CameraOverlayTuning.eyeOpenThreshold),
      );
    });

    test('manualFallbackMs is longer than autoCaptureMs', () {
      expect(
        CameraOverlayTuning.manualFallbackMs,
        greaterThan(CameraOverlayTuning.autoCaptureMs),
      );
    });
  });

  group('animatedSwitcherDedupeLayout', () {
    test('keeps current child and keyless previous children', () {
      const current = SizedBox(key: ValueKey('A'));
      const previous = [
        SizedBox(key: ValueKey('B')),
        SizedBox(),
      ];
      final result = animatedSwitcherDedupeLayout(current, previous);

      final stack = result as Stack;
      expect(stack.children.length, 3); // 2 previous + 1 current
    });

    test('drops previous child whose key matches the current key', () {
      const current = SizedBox(key: ValueKey('A'));
      const previous = [
        SizedBox(key: ValueKey('A')), // duplicate — must drop
        SizedBox(key: ValueKey('B')),
      ];
      final result = animatedSwitcherDedupeLayout(current, previous);

      final stack = result as Stack;
      expect(stack.children.length, 2); // 1 previous (B) + 1 current (A)
    });

    test('handles null current', () {
      const previous = [SizedBox(key: ValueKey('X'))];
      final result = animatedSwitcherDedupeLayout(null, previous);

      final stack = result as Stack;
      expect(stack.children.length, 1);
    });

    test('drops second occurrence of the same previous key', () {
      const previous = [
        SizedBox(key: ValueKey('X')),
        SizedBox(key: ValueKey('X')), // duplicate
        SizedBox(key: ValueKey('Y')),
      ];
      final result = animatedSwitcherDedupeLayout(null, previous);

      final stack = result as Stack;
      expect(stack.children.length, 2); // first X + Y
    });
  });

  group('computeOvalInImagePx', () {
    test('returns Rect.zero when screen size is null', () {
      final r = computeOvalInImagePx(
        screenSize: null,
        imageSize: const Size(1080, 1920),
        holeWidth: 300,
        holeHeight: 188,
      );
      expect(r, Rect.zero);
    });

    test('returns Rect.zero when image size is empty', () {
      final r = computeOvalInImagePx(
        screenSize: const Size(390, 844),
        imageSize: Size.zero,
        holeWidth: 300,
        holeHeight: 188,
      );
      expect(r, Rect.zero);
    });

    test('produces a centred rect when screen and image align (cover scale)', () {
      const screen = Size(390, 844);
      const image = Size(1080, 1920);
      final r = computeOvalInImagePx(
        screenSize: screen,
        imageSize: image,
        holeWidth: 300,
        holeHeight: 188,
      );
      // Centre of result should match centre of the image
      expect(r.center.dx, closeTo(image.width / 2, 0.5));
      expect(r.center.dy, closeTo(image.height / 2, 0.5));
      // Rect must be non-empty
      expect(r.width, greaterThan(0));
      expect(r.height, greaterThan(0));
    });
  });

  group('consensusHasMinimumData', () {
    test('null snapshot → false', () {
      expect(consensusHasMinimumData(null), isFalse);
    });
  });

  group('filterBlocksInHole', () {
    test('empty input → empty output (text and blocks)', () {
      final input = RecognizedText(text: '', blocks: const []);
      final out = filterBlocksInHole(input, const Size(1080, 1920));
      expect(out.blocks, isEmpty);
      expect(out.text, isEmpty);
    });
  });

  group('initialGuideText', () {
    test('face hole → oval prompt', () {
      expect(
        initialGuideText(isFaceHole: true),
        'Posiciona tu rostro en el óvalo',
      );
    });

    test('document hole → frame prompt', () {
      expect(
        initialGuideText(isFaceHole: false),
        'Encuadra el documento en el área',
      );
    });
  });

  group('loadingMessage', () {
    test('not loading → default capture string', () {
      expect(
        loadingMessage(isLoading: false, isBackSide: false),
        'Capturando...',
      );
    });

    test('loading + front side → flip-card hint', () {
      expect(
        loadingMessage(isLoading: true, isBackSide: false),
        'Anverso capturado\nAhora voltea el DNI',
      );
    });

    test('loading + back side → default capture string', () {
      expect(
        loadingMessage(isLoading: true, isBackSide: true),
        'Capturando...',
      );
    });
  });

  group('perfectSinceOnRecover', () {
    final base = DateTime(2026, 6, 5, 12);

    test('no previous drop → returns now (fresh window)', () {
      expect(
        perfectSinceOnRecover(now: base, lastCaptureableAt: null),
        base,
      );
    });

    test('within grace window → null (preserve existing perfectSince)', () {
      final prev = base.subtract(const Duration(milliseconds: 200));
      expect(
        perfectSinceOnRecover(now: base, lastCaptureableAt: prev),
        isNull,
      );
    });

    test('outside grace window → returns now (start fresh window)', () {
      final prev = base.subtract(const Duration(milliseconds: 1200));
      expect(
        perfectSinceOnRecover(now: base, lastCaptureableAt: prev),
        base,
      );
    });
  });

  group('shouldClearPerfectSince', () {
    final base = DateTime(2026, 6, 5, 12);

    test('null lastCaptureableAt → false', () {
      expect(
        shouldClearPerfectSince(now: base, lastCaptureableAt: null),
        isFalse,
      );
    });

    test('within grace window → false', () {
      final prev = base.subtract(const Duration(milliseconds: 200));
      expect(
        shouldClearPerfectSince(now: base, lastCaptureableAt: prev),
        isFalse,
      );
    });

    test('outside grace window → true', () {
      final prev = base.subtract(const Duration(milliseconds: 1200));
      expect(
        shouldClearPerfectSince(now: base, lastCaptureableAt: prev),
        isTrue,
      );
    });
  });

  group('BlinkLivenessTracker', () {
    test('starts undetected with zero blinks', () {
      final t = BlinkLivenessTracker();
      expect(t.isDetected, isFalse);
      expect(t.blinkCount, 0);
      expect(t.eyesWereClosed, isFalse);
    });

    test('null probabilities are treated as open (1.0) → no state change', () {
      final t = BlinkLivenessTracker();
      final r = t.update(leftEyeOpen: null, rightEyeOpen: null);
      expect(r.fullyConfirmed, isFalse);
      expect(t.eyesWereClosed, isFalse);
      expect(t.blinkCount, 0);
    });

    test('both eyes clearly open → no blink registered', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.95, rightEyeOpen: 0.95);
      expect(t.eyesWereClosed, isFalse);
      expect(t.blinkCount, 0);
    });

    test('both eyes clearly closed → enters eyesWereClosed state', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1);
      expect(t.eyesWereClosed, isTrue);
      expect(t.blinkCount, 0);
    });

    test('closed → open completes one blink', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1); // closed
      final r = t.update(leftEyeOpen: 0.9, rightEyeOpen: 0.9); // open
      expect(t.blinkCount, 1);
      expect(t.eyesWereClosed, isFalse);
      // With requiredBlinks=1, one complete blink confirms liveness.
      expect(t.isDetected, isTrue);
      expect(r.fullyConfirmed, isTrue);
    });

    test('mid-range probability between thresholds keeps state', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1); // closed
      // 0.4 is between closedThreshold (0.3) and openThreshold (0.5) → no
      // transition; eyes remain "wereClosed" until they fully open.
      final r = t.update(leftEyeOpen: 0.4, rightEyeOpen: 0.4);
      expect(t.eyesWereClosed, isTrue);
      expect(t.blinkCount, 0);
      expect(r.fullyConfirmed, isFalse);
    });

    test('one eye open + one eye closed → no transition', () {
      final t = BlinkLivenessTracker();
      // Asymmetric — neither bothOpen nor bothClosed conditions trigger.
      final r = t.update(leftEyeOpen: 0.95, rightEyeOpen: 0.1);
      expect(t.eyesWereClosed, isFalse);
      expect(t.blinkCount, 0);
      expect(r.fullyConfirmed, isFalse);
    });

    test('subsequent updates after detection are no-ops', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1);
      t.update(leftEyeOpen: 0.9, rightEyeOpen: 0.9);
      expect(t.isDetected, isTrue);
      // Another full blink does NOT increment beyond the confirmed state.
      final r = t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1);
      expect(r.fullyConfirmed, isFalse);
      expect(t.blinkCount, 1);
    });

    test('reset clears state back to initial', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1);
      t.update(leftEyeOpen: 0.9, rightEyeOpen: 0.9);
      expect(t.isDetected, isTrue);

      t.reset();
      expect(t.isDetected, isFalse);
      expect(t.blinkCount, 0);
      expect(t.eyesWereClosed, isFalse);
    });

    test('full sequence: open → closed → open registers exactly one blink', () {
      final t = BlinkLivenessTracker();
      t.update(leftEyeOpen: 0.95, rightEyeOpen: 0.95); // open (no-op)
      t.update(leftEyeOpen: 0.95, rightEyeOpen: 0.95); // open (no-op)
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1); // closed
      t.update(leftEyeOpen: 0.1, rightEyeOpen: 0.1); // still closed
      t.update(leftEyeOpen: 0.9, rightEyeOpen: 0.9); // open → blink!
      expect(t.blinkCount, 1);
      expect(t.isDetected, isTrue);
    });
  });

  group('expirationIfPast', () {
    test('null input → null', () {
      expect(expirationIfPast(null), isNull);
    });

    test('empty input → null', () {
      expect(expirationIfPast(''), isNull);
    });

    test('non DD/MM/YYYY input → null', () {
      expect(expirationIfPast('2024-01-15'), isNull);
      expect(expirationIfPast('15/01/24'), isNull);
      expect(expirationIfPast('abc'), isNull);
    });

    test('future date → null (still valid)', () {
      final future = DateTime.now().add(const Duration(days: 365));
      final raw =
          '${future.day.toString().padLeft(2, '0')}/'
          '${future.month.toString().padLeft(2, '0')}/'
          '${future.year}';
      expect(expirationIfPast(raw), isNull);
    });

    test('past date → returns parsed DateTime', () {
      const raw = '15/03/2020';
      final result = expirationIfPast(raw);
      expect(result, isNotNull);
      expect(result!.year, 2020);
      expect(result.month, 3);
      expect(result.day, 15);
    });

    test('trims whitespace before parsing', () {
      const raw = '  15/03/2020  ';
      expect(expirationIfPast(raw), isNotNull);
    });
  });
}
