import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// PR5 — presence migration into the [CaptureCoordinator].
///
/// The coordinator becomes the single owner of the document-present / absent
/// decision (previously split across `DniScannerState._setDocumentPresent` and
/// the top-level `documentPresent` predicate fed by `_frameCaptureable`). The
/// CURE for the device false-absent banner (#5543, 34ba2b8): FRONT presence is
/// OCR-document-based — a front DNI being READ this frame (side detected as
/// front / OCR text present) is PRESENT even when it has not yet stabilized into
/// a capture-ready signal and even when the quad reports `corners=0`. BACK
/// presence stays the quad's real signal (the textless back has no OCR proof).
/// Genuine removal (OCR empty + no quad) drops presence so the absent banner
/// still shows on a truly removed document.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

/// A front frame that detects the side but has not yet filled enough distinct
/// fields to stabilize: only the title anchor plus the document number, so the
/// machine is in extractingFront emitting `none` — NOT capture-ready yet. This
/// is the exact device frame that false-flagged absent: a present DNI being read
/// mid-extraction.
const _frontReadingText = 'DOCUMENTO NACIONAL DE IDENTIDAD\nDNI 16793105';

const _autoCaptureMs = 3000;

FrameInput _frontFrameAt(DateTime now, {bool quadFramingValid = false}) =>
    FrameInput(
      ocrText: _frontText,
      quadFramingValid: quadFramingValid,
      imuStill: true,
      now: now,
    );

FrameInput _frontReadingFrameAt(DateTime now) => FrameInput(
      ocrText: _frontReadingText,
      quadFramingValid: false,
      imuStill: true,
      now: now,
    );

FrameInput _emptyFrameAt(DateTime now, {bool quadFramingValid = false}) =>
    FrameInput(
      ocrText: '',
      quadFramingValid: quadFramingValid,
      imuStill: true,
      now: now,
    );

CaptureCoordinator _twoSided() => CaptureCoordinator(
      fields: DniFields.minimal(),
      idleFramesThreshold: 4,
      autoCaptureMs: _autoCaptureMs,
      gracePeriodMs: 600,
      minStableFrames: 1,
    );

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  group('CaptureDecision — AbsentBanner', () {
    test('CaptureAbsentBanner is a distinct CaptureDecision the widget renders',
        () {
      const absent = CaptureAbsentBanner();
      expect(absent, isA<CaptureDecision>());
    });
  });

  group('CaptureCoordinator.documentPresent — front (OCR-based, the CURE)', () {
    test(
      'a front DNI being READ mid-extraction is PRESENT even with the quad '
      'false (corners=0) and before any capture-ready signal — no false absent',
      () {
        final coordinator = _twoSided();

        // Frame 0 detects the front (frontDetected). Frame 1 is still reading
        // (only title + DNI), so the machine is in extractingFront emitting
        // `none` and is NOT capture-ready. The quad is false the whole time.
        coordinator.onFrame(_frontReadingFrameAt(t0));
        coordinator.onFrame(
          _frontReadingFrameAt(t0.add(const Duration(milliseconds: 120))),
        );

        expect(coordinator.phase, HuntPhase.extractingFront);
        expect(
          coordinator.documentPresent,
          isTrue,
          reason: 'a front document being read is present even before it '
              'stabilizes and even with corners=0 — this is the device cure',
        );
      },
    );

    test(
      'a genuinely removed front (OCR goes empty, no quad) is ABSENT so the '
      'banner still shows on a truly removed document',
      () {
        final coordinator = _twoSided();

        coordinator.onFrame(_frontReadingFrameAt(t0));
        // The card is removed: OCR empty, no quad, for sustained frames.
        for (var ms = 120; ms <= 600; ms += 120) {
          coordinator.onFrame(_emptyFrameAt(t0.add(Duration(milliseconds: ms))));
        }

        expect(
          coordinator.documentPresent,
          isFalse,
          reason: 'a removed front (empty OCR, no quad) must read absent',
        );
      },
    );
  });

  group('CaptureCoordinator.documentPresent — back (quad-based)', () {
    test(
      'a textless back with a sustained valid quad is PRESENT',
      () {
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
          backQuadDwellFrames: 3,
          autoCaptureMs: _autoCaptureMs,
          gracePeriodMs: 600,
          minStableFrames: 1,
          initialPhase: HuntPhase.waitingBack,
        );

        coordinator.onFrame(_emptyFrameAt(t0, quadFramingValid: true));

        expect(coordinator.documentPresent, isTrue);
      },
    );

    test(
      'a back with no quad (removed / textless empty view) is ABSENT',
      () {
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
          backQuadDwellFrames: 3,
          initialPhase: HuntPhase.waitingBack,
        );

        coordinator.onFrame(_emptyFrameAt(t0));

        expect(coordinator.documentPresent, isFalse);
      },
    );
  });

  group('CaptureCoordinator — removal during front extraction emits absent', () {
    test(
      'a front that latched extractingFront then is removed (empty frames) '
      'surfaces CaptureAbsentBanner and resets — it does NOT stay stuck '
      'emitting Scanning forever (the PR5 cure of the frozen golden)',
      () {
        final coordinator = _twoSided();

        coordinator.onFrame(_frontReadingFrameAt(t0)); // latches extractingFront

        final decisions = <CaptureDecision>[];
        for (var ms = 120; ms <= 120 + 600 + 600; ms += 120) {
          decisions.add(
            coordinator.onFrame(_emptyFrameAt(t0.add(Duration(milliseconds: ms)))),
          );
        }

        expect(
          decisions.whereType<CaptureAbsentBanner>(),
          isNotEmpty,
          reason: 'a removed front must surface the absent banner, not stay '
              'silently stuck in extractingFront',
        );
        expect(
          decisions.whereType<CaptureFire>(),
          isEmpty,
          reason: 'a removed front must never fire the shutter',
        );
      },
    );
  });
}
