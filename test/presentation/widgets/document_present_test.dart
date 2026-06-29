import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('documentPresent back side (#5540 quad-confirmed presence)', () {
    test('present when framing is valid AND the frame is capture-eligible', () {
      expect(
        documentPresent(
          framingValid: true,
          captureEligible: true,
          isFrontPhase: false,
        ),
        isTrue,
      );
    });

    test('absent when framing drops even if a stale capture-eligible flag stays',
        () {
      // Native-quad regime on the BACK: the card is removed, the quad isolate
      // reports framingValid=false. The back's only presence proof is the quad,
      // so even a stale captureEligible flag must not keep it present.
      expect(
        documentPresent(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: false,
        ),
        isFalse,
      );
    });

    test('absent when the frame is not capture-eligible even if framed', () {
      // The back lost its capture-ready signal so the frame stops being
      // capture-eligible; a stale framing flag must not keep it present.
      expect(
        documentPresent(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: false,
        ),
        isFalse,
      );
    });

    test('absent when both signals are false', () {
      expect(
        documentPresent(
          framingValid: false,
          captureEligible: false,
          isFrontPhase: false,
        ),
        isFalse,
      );
    });
  });

  group('documentPresent front side (#5543 side-aware presence)', () {
    test(
        'present when OCR-eligible even though the quad framing is invalid '
        '(text-dense front, corners=0)', () {
      // The Peru DNI front is text-dense: held still the native quad finds text
      // edges, not a clean 4-corner card boundary, so framingValid degrades to
      // false while the DNI IS present and OCR-confirmed. Front presence must
      // track the OCR-eligibility signal, not the quad, so the absent banner
      // does NOT show a false "No se detectó el documento".
      expect(
        documentPresent(
          framingValid: false,
          captureEligible: true,
          isFrontPhase: true,
        ),
        isTrue,
      );
    });

    test('present when OCR-eligible and the quad also happens to be valid', () {
      expect(
        documentPresent(
          framingValid: true,
          captureEligible: true,
          isFrontPhase: true,
        ),
        isTrue,
      );
    });

    test(
        'absent when OCR-eligibility drops on genuine removal even if a stale '
        'framing flag stays (#5540 still works on the front)', () {
      // The real device removal detector on the front is OCR going empty
      // (signal=none -> captureEligible=false). Removing the card must drop
      // front presence so the absent banner DOES show, even if a stale framing
      // flag lingers for a frame.
      expect(
        documentPresent(
          framingValid: true,
          captureEligible: false,
          isFrontPhase: true,
        ),
        isFalse,
      );
    });

    test('absent when both signals are false on the front', () {
      expect(
        documentPresent(
          framingValid: false,
          captureEligible: false,
          isFrontPhase: true,
        ),
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
