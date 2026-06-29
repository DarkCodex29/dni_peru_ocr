import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('manualButtonVisible (#5536 gate manual on auto-capture state)', () {
    test('is NOT visible while an auto-capture countdown is active, even when '
        'manual mode has been flagged', () {
      // Device truth (#5536): the controller manual-fallback flag can flip true
      // (early recoverManual escape or the per-side timer) while the widget is
      // running the 3-2-1 countdown. The manual button must NOT compete with a
      // live auto-capture, so it stays hidden while the countdown runs.
      final visible = manualButtonVisible(
        manualModeActive: true,
        countdownActive: true,
        autoCaptureProgressing: false,
      );
      expect(
        visible,
        isFalse,
        reason: 'manual button must be withheld while the 3-2-1 countdown is '
            'on screen so the user does not tap it instead of waiting for the '
            'auto-capture that is already firing',
      );
    });

    test('is NOT visible while the side is actively progressing toward capture '
        '(extracting dwell), even when manual mode has been flagged', () {
      // The back latches into an extracting phase and dwells toward
      // backCaptureReady; during this window the auto path is in progress and
      // the manual button must not surface prematurely.
      final visible = manualButtonVisible(
        manualModeActive: true,
        countdownActive: false,
        autoCaptureProgressing: true,
      );
      expect(
        visible,
        isFalse,
        reason: 'manual button must be withheld while a side is dwelling '
            'toward auto-capture so the manual stays a real fallback',
      );
    });

    test('IS visible when manual mode is flagged and no auto-capture is in '
        'progress (genuine fallback)', () {
      // After the auto window elapses on the current side with no countdown and
      // no active dwell, the manual button is the legitimate escape hatch.
      final visible = manualButtonVisible(
        manualModeActive: true,
        countdownActive: false,
        autoCaptureProgressing: false,
      );
      expect(
        visible,
        isTrue,
        reason: 'manual button must still appear as a genuine fallback when '
            'auto-capture is not progressing',
      );
    });

    test('is NOT visible when manual mode was never flagged', () {
      // Auto mode with no fallback flagged: only the auto path drives capture.
      final visible = manualButtonVisible(
        manualModeActive: false,
        countdownActive: false,
        autoCaptureProgressing: false,
      );
      expect(visible, isFalse);
    });

    test('is NOT visible when manual mode is flagged but BOTH countdown and '
        'dwell are active (still mid auto-capture)', () {
      final visible = manualButtonVisible(
        manualModeActive: true,
        countdownActive: true,
        autoCaptureProgressing: true,
      );
      expect(visible, isFalse);
    });
  });
}
