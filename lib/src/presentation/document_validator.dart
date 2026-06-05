import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'theme/kyc_theme.dart';
import '../infrastructure/tilt_calculator.dart';

/// Validates document framing via geometry + optional OCR matching.
///
/// When `ocrMatchesUser` is true, containment and fill thresholds relax
/// because OCR already confirmed the correct document.
class DocumentValidationResult {
  const DocumentValidationResult._({
    required this.message,
    required this.borderColor,
    required this.isCaptureable,
    this.failingGate,
  });

  final String message;
  final Color borderColor;
  final bool isCaptureable;

  /// Diagnostic-only — name of the gate that rejected the frame, or `null`
  /// when [isCaptureable] is true. Used by the G.1 telemetry overlay and
  /// Sentry breadcrumbs to pinpoint which gate is failing on JC's device.
  ///
  /// Stable string codes (do NOT translate — Sentry filters on these):
  ///   - `min_blocks`        : fewer recognized blocks than required
  ///   - `centering`         : group bounding box not inside the padded hole
  ///   - `fill_high`         : `fillRatio > _maxFillRatio` (too close)
  ///   - `fill_low`          : `fillRatio < requiredFill` (too far)
  ///   - `line_count`        : `< 5` blocks inside the hole (REQ-TILT-1)
  ///   - `tilt`              : `|tilt| > _maxTiltDegrees`
  final String? failingGate;

  static const double _holeNormW = 0.85;
  static const double _holeNormH = 0.65;
  static const double _edgeTol = 0.15;
  static const double _minFillRatio = 0.20;
  static const double _minFillRatioWithOcr = 0.15;
  static const double _maxFillRatio = 0.85;
  static const int _minBlocks = 2;
  static const int _minBlocksBack = 1;
  // Calibrated for 720p handheld capture: cornerPoint jitter (±2-3px per
  // line) produces 7-10° of median tilt noise on perfectly leveled
  // documents, plus ±3° of human steadiness slack. An 8° threshold sat
  // inside that noise floor and produced false-positive "Endereza" loops
  // (reported by JC). 15° accepts genuine leveled handheld captures while
  // still rejecting visibly skewed documents that would harm backend OCR.
  static const double _maxTiltDegrees = 15.0;

  /// Test seam — override to inject a fixed tilt value without constructing
  /// real MLKit cornerPoints. In production this is `null`, which causes
  /// [evaluate] to call [computeMedianTiltDegrees] directly.
  ///
  /// Usage in tests:
  /// ```dart
  /// DocumentValidationResult.tiltCalculator = (_) => 15.0;
  /// ```
  @visibleForTesting
  static double Function(RecognizedText)? tiltCalculator;

  static DocumentValidationResult evaluate({
    required RecognizedText recognizedText,
    required Size imageSize,
    required KycTheme theme,
    bool ocrMatchesUser = false,
    bool isBackSide = false,
  }) {
    final blocks = recognizedText.blocks;
    final requiredBlocks = isBackSide ? _minBlocksBack : _minBlocks;

    if (blocks.length < requiredBlocks) {
      return DocumentValidationResult._(
        message: 'Posiciona tu documento en el recuadro',
        borderColor: theme.white,
        isCaptureable: false,
        failingGate: 'min_blocks',
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
      return DocumentValidationResult._(
        message: 'Centra tu documento en el recuadro',
        borderColor: theme.accentOrange,
        isCaptureable: false,
        failingGate: 'centering',
      );
    }

    final fillRatio = (gbb.width * gbb.height) / (holeW * holeH);

    // Upper bound applies to BOTH sides — crop kills OCR + MRZ alike.
    if (fillRatio > _maxFillRatio) {
      return DocumentValidationResult._(
        message: 'Aléjate un poco — documento muy cerca',
        borderColor: theme.accentOrange,
        isCaptureable: false,
        failingGate: 'fill_high',
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
          borderColor: theme.accentOrange,
          isCaptureable: false,
          failingGate: 'fill_low',
        );
      }
    }

    // Line-count guard (REQ-TILT-1): fewer than 5 OCR lines within the hole
    // means the frame doesn't have enough text signal to compute a reliable
    // tilt — skip tilt entirely and ask user to realign the document.
    if (blocks.length < 5) {
      return DocumentValidationResult._(
        message: 'Alinea el documento dentro del recuadro',
        borderColor: theme.white,
        isCaptureable: false,
        failingGate: 'line_count',
      );
    }

    // Tilt check — applies to both front and back.
    // A skewed capture makes backend OCR fail, same as tilted MRZ.
    final tilt = (tiltCalculator ?? computeMedianTiltDegrees)(recognizedText);
    if (tilt.abs() > _maxTiltDegrees) {
      return DocumentValidationResult._(
        message: 'Endereza el documento',
        borderColor: theme.accentOrange,
        isCaptureable: false,
        failingGate: 'tilt',
      );
    }

    return DocumentValidationResult._(
      message: ocrMatchesUser
          ? '¡DNI verificado! Mantén quieto'
          : '¡Perfecto! Mantén el documento quieto',
      borderColor: theme.success,
      isCaptureable: true,
    );
  }
}
