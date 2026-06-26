import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:dni_peru_ocr/src/presentation/widgets/dni_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('flipBannerVisible (#5494 close paso1->paso2 gap)', () {
    test('IS visible during the FRONT in-flight processing window in two-sided '
        'mode (the dead window between the flash and waitingBack)', () {
      // Device truth (#5491): after the front shutter fires, the state stays
      // extractingFront with capture IN FLIGHT while the slow Camera2
      // takePicture/crop runs. phase only becomes waitingBack AFTER that
      // completes, so the flip guidance was invisible during the whole
      // processing window — a dead transition gap. The banner must show
      // continuously from the flash through to back scanning.
      final visible = flipBannerVisible(
        phase: HuntPhase.extractingFront,
        captureInFlight: true,
        twoSided: true,
      );
      expect(
        visible,
        isTrue,
        reason: 'flip guidance must cover the front in-flight processing '
            'window so there is no dead gap before waitingBack',
      );
    });

    test('IS visible once the machine reaches waitingBack (existing gate '
        'preserved)', () {
      final visible = flipBannerVisible(
        phase: HuntPhase.waitingBack,
        captureInFlight: false,
        twoSided: true,
      );
      expect(visible, isTrue);
    });

    test('is NOT visible while still scanning the front (no capture in flight)',
        () {
      // Before the front capture fires the user should not be told to flip.
      final visible = flipBannerVisible(
        phase: HuntPhase.extractingFront,
        captureInFlight: false,
        twoSided: true,
      );
      expect(visible, isFalse);
    });

    test('is NOT visible during front in-flight in SINGLE-SIDE mode (there is '
        'no back to flip to)', () {
      // Single-side capture (isBackSide != null) has no front-to-back
      // transition, so the flip guidance must never appear.
      final visible = flipBannerVisible(
        phase: HuntPhase.extractingFront,
        captureInFlight: true,
        twoSided: false,
      );
      expect(visible, isFalse);
    });

    test('is NOT visible during a BACK capture in flight (the flip already '
        'happened)', () {
      // Once on the back phase the flip is done; an in-flight back capture must
      // not re-show the flip guidance.
      final visible = flipBannerVisible(
        phase: HuntPhase.extractingBack,
        captureInFlight: true,
        twoSided: true,
      );
      expect(visible, isFalse);
    });

    test('is NOT visible while waiting for the front', () {
      final visible = flipBannerVisible(
        phase: HuntPhase.waitingFront,
        captureInFlight: false,
        twoSided: true,
      );
      expect(visible, isFalse);
    });
  });
}
