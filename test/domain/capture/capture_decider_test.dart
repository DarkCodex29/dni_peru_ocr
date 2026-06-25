import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaptureDecider', () {
    HuntResult completeResult({bool frontDetected = true, bool backDetected = true}) {
      final fields = ExtractedFields(
        documentNumber: '12345678',
        firstName: 'JUAN',
        lastName: 'PEREZ',
        secondLastName: 'GOMEZ',
        dateOfBirth: '04/12/1990',
        expirationDate: '18/11/2029',
      );
      return HuntResult(
        fields: fields,
        frontDetected: frontDetected,
        backDetected: backDetected,
        lastSeen: DocumentSide.back,
      );
    }

    HuntResult emptyResult() => HuntResult(
          fields: ExtractedFields(),
          frontDetected: false,
          backDetected: false,
          lastSeen: DocumentSide.unknown,
        );

    test('decides not ready when no fields and no stability', () {
      const decider = CaptureDecider();
      final signal = decider.decide(
        hunt: emptyResult(),
        framingStable: false,
      );
      expect(signal.shouldCapture, isFalse);
      expect(signal.phase, CapturePhase.waiting);
    });

    test('decides not ready when fields complete but framing unstable', () {
      const decider = CaptureDecider();
      final signal = decider.decide(
        hunt: completeResult(),
        framingStable: false,
      );
      expect(signal.shouldCapture, isFalse);
      expect(signal.phase, CapturePhase.fieldsComplete);
    });

    test('decides ready when fields complete and framing stable', () {
      const decider = CaptureDecider();
      final signal = decider.decide(
        hunt: completeResult(),
        framingStable: true,
      );
      expect(signal.shouldCapture, isTrue);
      expect(signal.phase, CapturePhase.readyToCapture);
    });

    test('reports needsFront when only back detected', () {
      const decider = CaptureDecider();
      final hunt = HuntResult(
        fields: ExtractedFields(documentNumber: '12345678'),
        frontDetected: false,
        backDetected: true,
        lastSeen: DocumentSide.back,
      );
      final signal = decider.decide(hunt: hunt, framingStable: false);
      expect(signal.phase, CapturePhase.needsFront);
    });

    test('reports needsBack when only front detected', () {
      const decider = CaptureDecider();
      final hunt = HuntResult(
        fields: ExtractedFields(documentNumber: '12345678'),
        frontDetected: true,
        backDetected: false,
        lastSeen: DocumentSide.front,
      );
      final signal = decider.decide(hunt: hunt, framingStable: false);
      expect(signal.phase, CapturePhase.needsBack);
    });

    test('reports gathering when both sides seen but fields incomplete', () {
      const decider = CaptureDecider();
      final hunt = HuntResult(
        fields: ExtractedFields(documentNumber: '12345678'),
        frontDetected: true,
        backDetected: true,
        lastSeen: DocumentSide.back,
      );
      final signal = decider.decide(hunt: hunt, framingStable: false);
      expect(signal.phase, CapturePhase.gathering);
    });

    test('shouldCapture stays false when waiting phase reaches stable', () {
      const decider = CaptureDecider();
      final signal = decider.decide(
        hunt: emptyResult(),
        framingStable: true,
      );
      expect(signal.shouldCapture, isFalse);
    });

    test('lightingValid false blocks capture even when fields and framing ok',
        () {
      const decider = CaptureDecider();
      final signal = decider.decide(
        hunt: completeResult(),
        framingStable: true,
        lightingValid: false,
      );
      expect(signal.shouldCapture, isFalse);
      expect(signal.phase, CapturePhase.fieldsComplete);
    });

    test('lightingValid defaults to true so existing call sites still capture',
        () {
      const decider = CaptureDecider();
      final signal = decider.decide(
        hunt: completeResult(),
        framingStable: true,
      );
      expect(signal.shouldCapture, isTrue);
    });
  });
}
