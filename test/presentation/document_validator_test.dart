import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

// Helper: maps a result's failingGate to a Color via ValidationGateColors,
// mirroring what the presentation layer does after PR4.
Color _resultColor(DocumentValidationResult result) =>
    ValidationGateColors.colorFor(result.failingGate, kTheme);

/// Creates a [TextBlock] with sensible defaults for testing.
/// Only override the fields your test cares about.
TextBlock makeBlock({
  Rect boundingBox = const Rect.fromLTWH(100, 100, 200, 100),
  String text = 'dummy text',
}) {
  return TextBlock(
    text: text,
    lines: [],
    boundingBox: boundingBox,
    recognizedLanguages: ['es'],
    cornerPoints: [
      math.Point(boundingBox.left.toInt(), boundingBox.top.toInt()),
      math.Point(boundingBox.right.toInt(), boundingBox.top.toInt()),
      math.Point(boundingBox.right.toInt(), boundingBox.bottom.toInt()),
      math.Point(boundingBox.left.toInt(), boundingBox.bottom.toInt()),
    ],
  );
}

/// Standard image size used across all tests (1920×1080).
const kTestImageSize = Size(1920, 1080);

/// Default theme used across all tests.
final kTheme = KycTheme.defaults();

// Geometry reference for kTestImageSize (_edgeTol=0.15, _minFillRatio=0.20,
// _minFillRatioWithOcr=0.15):
//   paddedHole = LTRB(-144, 27, 2064, 1053)
//   holeArea   = 1632 * 702 = 1145664

/// A single bounding box inside the paddedHole with fill ≈ 0.672 — the
/// canonical "good block" used as default across tests.
const kGoodDocumentBox = Rect.fromLTRB(250, 250, 1650, 800);

/// Builds a [RecognizedText] with [count] blocks all sharing the same bounding box.
RecognizedText makeRecognizedText({
  required int count,
  Rect boundingBox = kGoodDocumentBox,
}) {
  final blocks = List.generate(
    count,
    (_) => makeBlock(boundingBox: boundingBox),
  );
  return RecognizedText(text: 'dummy', blocks: blocks);
}

void main() {
  // Group 1 — Presence validation (Step 1) — _minBlocks = 2
  group('Presence validation (Step 1)', () {
    test('0 blocks → not capturable, white border, "Posiciona" message', () {
      final result = DocumentValidationResult.evaluate(
        recognizedText: makeRecognizedText(count: 0),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(_resultColor(result), kTheme.white);
      expect(result.message, 'Posiciona tu documento en el recuadro');
    });

    test('1 block → not capturable', () {
      final result = DocumentValidationResult.evaluate(
        recognizedText: makeRecognizedText(count: 1),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(_resultColor(result), kTheme.white);
      expect(result.message, 'Posiciona tu documento en el recuadro');
    });

    test(
      'boundary: 2 blocks inside hole with good fill → NOT capturable (line-count guard fires)',
      () {
        // 2 blocks passes presence (≥2) but hits the < 5 line-count guard → align_document.
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 2),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Alinea el documento dentro del recuadro');
      },
    );

    test(
      '3 blocks inside hole with good fill → NOT capturable (line-count guard)',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 3),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Alinea el documento dentro del recuadro');
      },
    );

    test(
      '5 blocks inside hole with good fill → capturable (passes line-count guard)',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isTrue);
      },
    );
  });

  // Group 2 — Containment validation (Step 2)
  // paddedHole = LTRB(-144, 27, 2064, 1053) with 15% tolerance (_edgeTol=0.15)
  group('Containment validation (Step 2)', () {
    // 5 blocks to pass line-count guard and reach tilt/success path.
    RecognizedText textWith5Blocks(Rect box) =>
        makeRecognizedText(count: 5, boundingBox: box);

    // 2 blocks is enough for containment failures — containment fires before
    // the line-count guard.
    RecognizedText textWith2Blocks(Rect box) =>
        makeRecognizedText(count: 2, boundingBox: box);

    test(
      'GBB clearly outside padded hole to the left → not capturable, orange',
      () {
        const box = Rect.fromLTRB(-200, 250, 1000, 750);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith2Blocks(box),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, 'Centra tu documento en el recuadro');
      },
    );

    test('GBB outside padded hole to the right → not capturable', () {
      const box = Rect.fromLTRB(250, 250, 2100, 750);
      final result = DocumentValidationResult.evaluate(
        recognizedText: textWith2Blocks(box),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(_resultColor(result), kTheme.accentOrange);
      expect(result.message, 'Centra tu documento en el recuadro');
    });

    test('GBB outside padded hole to the top → not capturable', () {
      const box = Rect.fromLTRB(250, 20, 1650, 500);
      final result = DocumentValidationResult.evaluate(
        recognizedText: textWith2Blocks(box),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(_resultColor(result), kTheme.accentOrange);
      expect(result.message, 'Centra tu documento en el recuadro');
    });

    test('GBB outside padded hole to the bottom → not capturable', () {
      // bottom=1060 > paddedHole.bottom(1053); narrow width keeps fill ≤ 0.85
      const box = Rect.fromLTRB(350, 250, 950, 1060);
      final result = DocumentValidationResult.evaluate(
        recognizedText: textWith2Blocks(box),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(_resultColor(result), kTheme.accentOrange);
      expect(result.message, 'Centra tu documento en el recuadro');
    });

    test(
      'boundary: GBB at exactly paddedHole edge → capturable',
      () {
        // Box sits inside paddedHole with fill ≤ 0.85; 5 blocks for guard bypass.
        const box = Rect.fromLTRB(200, 103, 1650, 750);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith5Blocks(box),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isTrue);
      },
    );

    test('boundary: GBB barely past left tolerance → not capturable', () {
      // left=-145 < paddedHole.left(-144) → fails containment
      const box = Rect.fromLTRB(-145, 250, 655, 800);
      final result = DocumentValidationResult.evaluate(
        recognizedText: textWith2Blocks(box),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(result.message, 'Centra tu documento en el recuadro');
    });
  });

  // Group 3 — Fill ratio validation (Step 3) — _minFillRatio = 0.20
  // holeArea = 1632 * 702 = 1145664
  group('Fill ratio validation (Step 3)', () {
    // 2 blocks for failure tests (fill check fires before guard → early return).
    RecognizedText textWith2Blocks(Rect box) =>
        makeRecognizedText(count: 2, boundingBox: box);

    // 5 blocks for success/capturable tests (must pass line-count guard).
    RecognizedText textWith5Blocks(Rect box) =>
        makeRecognizedText(count: 5, boundingBox: box);

    test(
      'GBB inside hole but tiny (fill ≪ 0.20) → not capturable, orange, "Acércate"',
      () {
        const box = Rect.fromLTRB(400, 300, 500, 400);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith2Blocks(box),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, 'Acércate un poco más');
      },
    );

    test('GBB inside hole with fill ≈ 0.36 → capturable', () {
      const box = Rect.fromLTRB(300, 200, 980, 810);
      final result = DocumentValidationResult.evaluate(
        recognizedText: textWith5Blocks(box),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isTrue);
    });

    test('GBB inside hole with fill ≈ 0.10 → not capturable', () {
      const box = Rect.fromLTRB(400, 250, 740, 590);
      final result = DocumentValidationResult.evaluate(
        recognizedText: textWith2Blocks(box),
        imageSize: kTestImageSize,
      );

      expect(result.isCaptureable, isFalse);
      expect(_resultColor(result), kTheme.accentOrange);
      expect(result.message, 'Acércate un poco más');
    });
  });

  // Group 4 — Success case (Step 4)
  group('Success case (Step 4)', () {
    test(
      '5 blocks, well-positioned, good fill → capturable, green, "¡Perfecto!"',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isTrue);
        expect(_resultColor(result), kTheme.success);
        expect(result.message, '¡Perfecto! Mantén el documento quieto');
      },
    );

    test(
      '4 blocks, well-positioned → NOT capturable (line-count guard fires)',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 4),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Alinea el documento dentro del recuadro');
      },
    );
  });

  // Group 5 — Validation order
  group('Validation order', () {
    test(
      'presence checked before containment: 1 block even if well-positioned → Step 1 message',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(
            count: 1,
            boundingBox: kGoodDocumentBox,
          ),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.white);
        expect(result.message, 'Posiciona tu documento en el recuadro');
      },
    );

    test(
      'containment checked before fill: 2 blocks outside hole even if large → Step 2 message',
      () {
        // GBB left=-200 < paddedHole.left(-144) → containment fires before fill
        const outsideBox = Rect.fromLTRB(-200, 250, 1650, 750);
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 2, boundingBox: outsideBox),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, 'Centra tu documento en el recuadro');
      },
    );
  });

  // Group 6 — OCR match relaxation
  group('OCR match relaxation', () {
    // 5 blocks for capturable paths (must pass line-count guard).
    RecognizedText textWith5Blocks(Rect box) =>
        makeRecognizedText(count: 5, boundingBox: box);

    // 2 blocks for failure paths where early returns fire before the guard.
    RecognizedText textWith2Blocks(Rect box) =>
        makeRecognizedText(count: 2, boundingBox: box);

    test(
      'ocrMatchesUser=true skips containment check → capturable even if outside paddedHole',
      () {
        // left=-200 fails containment without OCR; narrow width keeps fill ≤ 0.85
        const box = Rect.fromLTRB(-200, 250, 600, 800);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith5Blocks(box),
          imageSize: kTestImageSize,
          ocrMatchesUser: true,
        );

        expect(result.isCaptureable, isTrue);
        expect(_resultColor(result), kTheme.success);
        expect(result.message, '¡DNI verificado! Mantén quieto');
      },
    );

    test(
      'ocrMatchesUser=true uses lower fill threshold → capturable with small doc',
      () {
        // fill ≈ 0.196 passes _minFillRatioWithOcr=0.15 but would fail _minFillRatio=0.20
        const box = Rect.fromLTRB(400, 250, 900, 700);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith5Blocks(box),
          imageSize: kTestImageSize,
          ocrMatchesUser: true,
        );

        expect(result.isCaptureable, isTrue);
        expect(result.message, '¡DNI verificado! Mantén quieto');
      },
    );

    test(
      'ocrMatchesUser=true still fails if fill is very low',
      () {
        // fill ≈ 0.009 < 0.15 — below even the relaxed OCR threshold
        const box = Rect.fromLTRB(400, 300, 500, 400);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith2Blocks(box),
          imageSize: kTestImageSize,
          ocrMatchesUser: true,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Acerca un poco más el documento');
      },
    );

    test(
      'ocrMatchesUser=false with box outside paddedHole fails containment',
      () {
        // left=-200 < paddedHole.left(-144); narrow box keeps fill ≤ 0.85
        const box = Rect.fromLTRB(-200, 250, 600, 800);
        final result = DocumentValidationResult.evaluate(
          recognizedText: textWith2Blocks(box),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Centra tu documento en el recuadro');
      },
    );
  });

  // Group 7 — Upper fill-ratio bound (_maxFillRatio = 0.85)
  group('Upper fill-ratio bound — too close (Fix #1)', () {
    // Fill > 0.85 fires BEFORE line-count guard → 2 blocks works for failure.
    RecognizedText front2Blocks(Rect box) =>
        makeRecognizedText(count: 2, boundingBox: box);

    RecognizedText back2Blocks(Rect box) =>
        makeRecognizedText(count: 2, boundingBox: box);

    // 5 blocks for capturable boundary test (fill ≤ 0.85 passes, needs guard bypass).
    RecognizedText front5Blocks(Rect box) =>
        makeRecognizedText(count: 5, boundingBox: box);

    test(
      'front: fillRatio > 0.85 → not capturable, orange, "Aléjate"',
      () {
        // W=1580, H=618 → area=976440 → fill≈0.852 > 0.85
        const box = Rect.fromLTRB(170, 111, 1750, 729);
        final result = DocumentValidationResult.evaluate(
          recognizedText: front2Blocks(box),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, contains('Aléjate'));
      },
    );

    test(
      'back: fillRatio > 0.85 → not capturable, orange, "Aléjate" (applies to back too)',
      () {
        const box = Rect.fromLTRB(170, 111, 1750, 729);
        final result = DocumentValidationResult.evaluate(
          recognizedText: back2Blocks(box),
          imageSize: kTestImageSize,
          isBackSide: true,
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, contains('Aléjate'));
      },
    );

    test(
      'boundary: fillRatio exactly at 0.85 → capturable (boundary is inclusive)',
      () {
        // W=1560, H=624 → area=973440 → fill≈0.8496 ≤ 0.85; 5 blocks for guard bypass
        const box = Rect.fromLTRB(180, 108, 1740, 732);
        final result = DocumentValidationResult.evaluate(
          recognizedText: front5Blocks(box),
          imageSize: kTestImageSize,
        );

        expect(result.isCaptureable, isTrue);
      },
    );
  });

  // Group 9 — Line-count guard (REQ-TILT-1): tilt gate skipped when < 5 OCR lines
  group('Line-count guard — tilt skipped when < 5 OCR lines (REQ-TILT-1)', () {
    // A tilt of 20° would trigger "Endereza" — the line-count guard must
    // prevent the tilt gate from running when there are fewer than 5 blocks.
    double tilt20(RecognizedText _) => 20.0;

    test(
      '0 OCR lines → isCaptureable=false, tilt NOT evaluated (no Endereza message)',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 0),
          imageSize: kTestImageSize,
          tiltCalculator: tilt20,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, isNot('Endereza el documento'));
      },
    );

    test(
      '4 OCR lines → isCaptureable=false, message="align_document", tilt NOT evaluated',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 4),
          imageSize: kTestImageSize,
          tiltCalculator: tilt20,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Alinea el documento dentro del recuadro');
      },
    );

    test(
      '5 OCR lines → tilt gate runs; injected 20° tilt → "Endereza" (not guard)',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          tiltCalculator: tilt20,
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Endereza el documento');
      },
    );
  });

  // Group 8 — Tilt detection (Step 4) — _maxTiltDegrees = 15.0
  group('Tilt detection (Step 4)', () {
    double tiltOf(double degrees) => degrees;

    test(
      'front: tilt 20° (above 15° threshold) → not capturable, orange, "Endereza"',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          tiltCalculator: (_) => tiltOf(20),
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, 'Endereza el documento');
      },
    );

    test(
      'back: tilt 20° also returns "Endereza"',
      () {
        // Back side: _minBlocksBack = 1, so presence passes with 1 block.
        // But line-count guard requires 5 — use 5 blocks.
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          isBackSide: true,
          tiltCalculator: (_) => tiltOf(20),
        );

        expect(result.isCaptureable, isFalse);
        expect(_resultColor(result), kTheme.accentOrange);
        expect(result.message, 'Endereza el documento');
      },
    );

    test(
      'front: tilt 5° (below threshold) passes tilt check → capturable',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          tiltCalculator: (_) => tiltOf(5),
        );

        expect(result.isCaptureable, isTrue);
      },
    );

    test(
      'front: tilt 12° (leveled handheld 720p, within noise floor) → capturable',
      () {
        // A leveled DNI captured handheld at 720p produces median tilts of 7-10°
        // from cornerPoint jitter (±2-3 px/line) plus human steadiness slack
        // (±3°). 12° must be accepted to avoid a false-positive "Endereza" loop.
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          tiltCalculator: (_) => tiltOf(12),
        );

        expect(result.isCaptureable, isTrue);
      },
    );

    test(
      'tilt exactly at threshold (15°) passes — boundary is inclusive',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          tiltCalculator: (_) => tiltOf(15),
        );

        expect(result.isCaptureable, isTrue);
      },
    );

    test(
      'negative tilt -20° is detected as tilted (abs > threshold)',
      () {
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5),
          imageSize: kTestImageSize,
          tiltCalculator: (_) => tiltOf(-20),
        );

        expect(result.isCaptureable, isFalse);
        expect(result.message, 'Endereza el documento');
      },
    );

    test(
      'tilt check runs AFTER fill ratio — fill too low still gives fill message',
      () {
        // Fill check fires before tilt: even with tilt=20°, a tiny box still
        // returns the fill message, not "Endereza".
        const smallBox = Rect.fromLTRB(400, 300, 500, 400); // fill ≈ 0.009
        final result = DocumentValidationResult.evaluate(
          recognizedText: makeRecognizedText(count: 5, boundingBox: smallBox),
          imageSize: kTestImageSize,
          tiltCalculator: (_) => tiltOf(20),
        );

        expect(result.message, 'Acércate un poco más');
      },
    );
  });
}
