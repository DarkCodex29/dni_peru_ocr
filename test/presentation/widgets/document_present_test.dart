import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('documentPresent (#5540 countdown reset on document loss)', () {
    test('present when framing is valid AND the frame is capture-eligible', () {
      expect(
        documentPresent(framingValid: true, captureEligible: true),
        isTrue,
      );
    });

    test('absent when framing drops even if a stale capture-eligible flag stays',
        () {
      // Native-quad regime: the card is removed, the quad isolate reports
      // framingValid=false. Even if the last OCR frame left captureEligible
      // true, the document is no longer present.
      expect(
        documentPresent(framingValid: false, captureEligible: true),
        isFalse,
      );
    });

    test('absent when the frame is not capture-eligible even if framed', () {
      // The front lost its OCR confirmation (signal=none) so the frame stops
      // being capture-eligible; a stale framing flag must not keep it present.
      expect(
        documentPresent(framingValid: true, captureEligible: false),
        isFalse,
      );
    });

    test('absent when both signals are false', () {
      expect(
        documentPresent(framingValid: false, captureEligible: false),
        isFalse,
      );
    });
  });

  group('documentAbsentBannerVisible (#5540 top-banner warning)', () {
    test('visible when the document is absent while scanning a side', () {
      expect(
        documentAbsentBannerVisible(
          documentPresent: false,
          phase: HuntPhase.extractingFront,
        ),
        isTrue,
      );
    });

    test('visible when the document is absent on the back side', () {
      expect(
        documentAbsentBannerVisible(
          documentPresent: false,
          phase: HuntPhase.extractingBack,
        ),
        isTrue,
      );
    });

    test('hidden once the document is present again', () {
      expect(
        documentAbsentBannerVisible(
          documentPresent: true,
          phase: HuntPhase.extractingFront,
        ),
        isFalse,
      );
    });

    test('hidden in the done phase even if no document is in view', () {
      // After both sides are captured the scanner is processing; a missing
      // document there is expected and must not surface the warning.
      expect(
        documentAbsentBannerVisible(
          documentPresent: false,
          phase: HuntPhase.done,
        ),
        isFalse,
      );
    });
  });
}
