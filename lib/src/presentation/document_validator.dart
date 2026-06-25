import 'dart:math';
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/entities/document_side.dart';
import '../domain/entities/validation_gate.dart';
import '../infrastructure/tilt_calculator.dart';

/// Result of evaluating a document frame against quality gates.
class DocumentValidationResult {
  const DocumentValidationResult._({
    required this.message,
    required this.isCaptureable,
    this.failingGate,
  });

  @visibleForTesting
  DocumentValidationResult.forTest({required bool isCaptureable})
      : this._(
          message: '',
          isCaptureable: isCaptureable,
        );

  const DocumentValidationResult.captureable()
      : message = '',
        isCaptureable = true,
        failingGate = null;

  final String message;
  final bool isCaptureable;

  final ValidationGate? failingGate;

  static const double _holeNormW = 0.85;
  static const double _holeNormH = 0.65;
  static const double _edgeTol = 0.15;
  static const double _minFillRatio = 0.20;
  static const double _minFillRatioWithOcr = 0.15;
  static const double _maxFillRatio = 0.85;
  static const int _minBlocks = 2;
  static const int _minBlocksBack = 1;

  static const double _maxTiltDegrees = 15.0;

  /// Evaluates document framing from [recognizedText] against [imageSize].
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

    final detectedSide =
        const DocumentSideDetector().detect(recognizedText.text);
    if (!isBackSide && detectedSide == DocumentSide.back) {
      return const DocumentValidationResult._(
        message: 'Estás mostrando el reverso. Voltea al frente del DNI.',
        isCaptureable: false,
        failingGate: ValidationGate.sideMismatch,
      );
    }
    if (isBackSide && detectedSide == DocumentSide.front) {
      return const DocumentValidationResult._(
        message: 'Estás mostrando el frente. Voltea al reverso del DNI.',
        isCaptureable: false,
        failingGate: ValidationGate.sideMismatch,
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

    final isContained = gbb.left >= paddedHole.left &&
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

    if (fillRatio > _maxFillRatio) {
      return const DocumentValidationResult._(
        message: 'Aléjate un poco — documento muy cerca',
        isCaptureable: false,
        failingGate: ValidationGate.fillHigh,
      );
    }

    if (!isBackSide) {
      final requiredFill =
          ocrMatchesUser ? _minFillRatioWithOcr : _minFillRatio;

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

    if (blocks.length < 5) {
      return const DocumentValidationResult._(
        message: 'Alinea el documento dentro del recuadro',
        isCaptureable: false,
        failingGate: ValidationGate.lineCount,
      );
    }

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
