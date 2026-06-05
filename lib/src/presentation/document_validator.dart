import 'dart:math';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/entities/validation_gate.dart';
import '../infrastructure/tilt_calculator.dart';

/// Validates document framing via geometry + optional OCR matching.
///
/// When `ocrMatchesUser` is true, containment and fill thresholds relax
/// because OCR already confirmed the correct document.
class DocumentValidationResult {
  const DocumentValidationResult._({
    required this.message,
    required this.isCaptureable,
    this.failingGate,
  });

  /// Test seam constructor — bypasses all gate logic for unit-test isolation.
  ///
  /// Use only in tests to build a minimal result when the full [evaluate]
  /// pipeline (ML Kit + Flutter `Size`) is not available. Only [isCaptureable]
  /// is meaningful on instances created this way; [message] is a stub value.
  @visibleForTesting
  DocumentValidationResult.forTest({required bool isCaptureable})
      : this._(
          message: '',
          isCaptureable: isCaptureable,
        );

  final String message;
  final bool isCaptureable;

  /// The gate that rejected this frame, or `null` when [isCaptureable] is true.
  ///
  /// Use [failingGate.sentryCode] for stable Sentry breadcrumb codes.
  /// All possible gates are enumerated in [ValidationGate].
  final ValidationGate? failingGate;

  static const double _holeNormW = 0.85;
  static const double _holeNormH = 0.65;
  static const double _edgeTol = 0.15;
  static const double _minFillRatio = 0.20;
  static const double _minFillRatioWithOcr = 0.15;
  static const double _maxFillRatio = 0.85;
  static const int _minBlocks = 2;
  static const int _minBlocksBack = 1;

  /// Maximum acceptable median document tilt before the gate rejects the
  /// frame and asks the user to straighten the card.
  ///
  /// Calibrated for 720p handheld capture: cornerPoint jitter sits at
  /// ±2–3 px per line which translates to roughly 7–10° of median tilt
  /// noise on a perfectly level document, on top of ±3° of human-hand
  /// steadiness slack. Anything tighter than ~12° falls inside the noise
  /// floor and produces false-positive "Endereza" prompts; the 15°
  /// threshold accepts genuine leveled handheld captures while still
  /// rejecting documents tilted enough to degrade backend OCR.
  static const double _maxTiltDegrees = 15.0;

  /// Evaluates document framing from [recognizedText] against [imageSize].
  ///
  /// [tiltCalculator] is an injectable function used to compute the median
  /// document tilt in degrees. Defaults to [computeMedianTiltDegrees], the
  /// production implementation backed by ML Kit corner points. Tests inject
  /// a fixed value to bypass the full geometry pipeline without setting up
  /// real corner-point geometry.
  static DocumentValidationResult evaluate({
    required RecognizedText recognizedText,
    required Size imageSize,
    bool ocrMatchesUser = false,
    bool isBackSide = false,
    double Function(RecognizedText) tiltCalculator = computeMedianTiltDegrees,
  }) {
    final blocks = recognizedText.blocks;
    final requiredBlocks = isBackSide ? _minBlocksBack : _minBlocks;

    if (blocks.length < requiredBlocks) {
      return const DocumentValidationResult._(
        message: 'Posiciona tu documento en el recuadro',
        isCaptureable: false,
        failingGate: ValidationGate.minBlocks,
      );
    }

    final holeW = imageSize.width * _holeNormW;
    final holeH = imageSize.height * _holeNormH;
    final holeRect = Rect.fromCenter(
      center: Offset(imageSize.width / 2, imageSize.height / 2),
      width: holeW,
      height: holeH,
    );

    double gLeft = double.infinity;
    double gTop = double.infinity;
    double gRight = double.negativeInfinity;
    double gBottom = double.negativeInfinity;

    for (final block in blocks) {
      final b = block.boundingBox;
      gLeft = min(gLeft, b.left);
      gTop = min(gTop, b.top);
      gRight = max(gRight, b.right);
      gBottom = max(gBottom, b.bottom);
    }

    final gbb = Rect.fromLTRB(gLeft, gTop, gRight, gBottom);

    final tolX = imageSize.width * _edgeTol;
    final tolY = imageSize.height * _edgeTol;
    final paddedHole = Rect.fromLTRB(
      holeRect.left - tolX,
      holeRect.top - tolY,
      holeRect.right + tolX,
      holeRect.bottom + tolY,
    );

    final isContained =
        gbb.left >= paddedHole.left &&
        gbb.top >= paddedHole.top &&
        gbb.right <= paddedHole.right &&
        gbb.bottom <= paddedHole.bottom;

    if (!isContained && !ocrMatchesUser && !isBackSide) {
      return const DocumentValidationResult._(
        message: 'Centra tu documento en el recuadro',
        isCaptureable: false,
        failingGate: ValidationGate.centering,
      );
    }

    final fillRatio = (gbb.width * gbb.height) / (holeW * holeH);

    // Upper bound applies to BOTH sides — crop kills OCR + MRZ alike.
    if (fillRatio > _maxFillRatio) {
      return const DocumentValidationResult._(
        message: 'Aléjate un poco — documento muy cerca',
        isCaptureable: false,
        failingGate: ValidationGate.fillHigh,
      );
    }

    // Lower bound only on front — back is MRZ-dominant and less affected.
    if (!isBackSide) {
      final requiredFill = ocrMatchesUser
          ? _minFillRatioWithOcr
          : _minFillRatio;

      if (fillRatio < requiredFill) {
        return DocumentValidationResult._(
          message: ocrMatchesUser
              ? 'Acerca un poco más el documento'
              : 'Acércate un poco más',
          isCaptureable: false,
          failingGate: ValidationGate.fillLow,
        );
      }
    }

    // Line-count guard (REQ-TILT-1): fewer than 5 OCR lines within the hole
    // means the frame doesn't have enough text signal to compute a reliable
    // tilt — skip tilt entirely and ask user to realign the document.
    if (blocks.length < 5) {
      return const DocumentValidationResult._(
        message: 'Alinea el documento dentro del recuadro',
        isCaptureable: false,
        failingGate: ValidationGate.lineCount,
      );
    }

    // Tilt check — applies to both front and back.
    // A skewed capture makes backend OCR fail, same as tilted MRZ.
    final tilt = tiltCalculator(recognizedText);
    if (tilt.abs() > _maxTiltDegrees) {
      return const DocumentValidationResult._(
        message: 'Endereza el documento',
        isCaptureable: false,
        failingGate: ValidationGate.tilt,
      );
    }

    return DocumentValidationResult._(
      message: ocrMatchesUser
          ? '¡DNI verificado! Mantén quieto'
          : '¡Perfecto! Mantén el documento quieto',
      isCaptureable: true,
    );
  }
}
