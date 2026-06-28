import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/presentation/framing/framing_signal.dart';

void main() {
  // FramingSignal unifies the four side-aware quad reads in DniScannerState
  // (#5543) into one value type. It carries the raw quad framing flag (a
  // non-blocking annotation that NEVER vetoes capture), the OCR-derived
  // capture-eligibility (the BLOCKING signal), and the side context. Each
  // accessor reproduces, byte-for-byte, the exact output of the fork it
  // replaces, so routing the call sites through it changes no behavior.

  group('FramingSignal.fireFramingValid (replaces _fireFramingValid #5543)', () {
    test('FRONT degrades framing OPEN — always valid regardless of the quad', () {
      // _isFrontPhase() ? true : _framingValid  with isFront=true => true.
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: true,
        ).fireFramingValid,
        isTrue,
      );
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: true,
          isFrontPhase: true,
        ).fireFramingValid,
        isTrue,
      );
    });

    test('BACK keeps the strict live quad gate — tracks framingValid', () {
      // isFront=false => _framingValid passthrough.
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: true,
          isFrontPhase: false,
        ).fireFramingValid,
        isTrue,
      );
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: false,
        ).fireFramingValid,
        isFalse,
      );
    });
  });

  group('FramingSignal.documentPresent (replaces documentPresent() #5540/#5543)',
      () {
    test('FRONT presence tracks capture-eligibility only (quad ignored)', () {
      // Text-dense front: quad corners=0 (framingValid=false) but the
      // OCR-confirmed DNI is present. Front presence => captureEligible.
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: true,
        ).documentPresent,
        isTrue,
      );
      // Genuine removal: OCR empty => captureEligible=false => absent even if a
      // stale framing flag lingers.
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: true,
        ).documentPresent,
        isFalse,
      );
    });

    test('BACK presence is the strict quad AND eligibility conjunction', () {
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: true,
          isFrontPhase: false,
        ).documentPresent,
        isTrue,
      );
      // Quad drop on the back drops presence even with a stale eligible flag.
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: false,
        ).documentPresent,
        isFalse,
      );
      // Lost eligibility drops presence even if framed.
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: false,
        ).documentPresent,
        isFalse,
      );
    });
  });

  group('FramingSignal.quadFramingValid (replaces the raw _framingValid '
      'overlay read — the non-blocking annotation)', () {
    test('exposes the raw quad flag unchanged, independent of side or eligibility',
        () {
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: true,
        ).quadFramingValid,
        isTrue,
      );
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: false,
        ).quadFramingValid,
        isFalse,
      );
    });
  });

  group('FramingSignal.dispatchEmptyOcrBackTrigger (replaces '
      'resolveEmptyOcrRoute() #5523)', () {
    test('back phase with a valid quad dispatches the back trigger', () {
      // framingValid && !isFront => true.
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: false,
        ).dispatchEmptyOcrBackTrigger,
        isTrue,
      );
    });

    test('no valid quad on a back phase skips (blank frame is not a document)',
        () {
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: false,
          isFrontPhase: false,
        ).dispatchEmptyOcrBackTrigger,
        isFalse,
      );
    });

    test('front phase with a valid quad skips (front stays OCR-triggered)', () {
      expect(
        const FramingSignal(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: true,
        ).dispatchEmptyOcrBackTrigger,
        isFalse,
      );
    });

    test('front phase with no quad skips', () {
      expect(
        const FramingSignal(
          framingValid: false,
          captureEligible: false,
          isFrontPhase: true,
        ).dispatchEmptyOcrBackTrigger,
        isFalse,
      );
    });
  });
}
