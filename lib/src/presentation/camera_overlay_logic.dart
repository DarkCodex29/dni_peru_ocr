import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Tuning constants shared by the camera overlay state machine.
class CameraOverlayTuning {
  const CameraOverlayTuning._();

  static const int autoCaptureMs = 1500;
  static const int gracePeriodMs = 600;
  static const int minStableFrames = 2;
  static const int requiredBlinks = 1;
  static const double eyeOpenThreshold = 0.5;
  static const double eyeClosedThreshold = 0.3;
  static const int manualFallbackMs = 15000;
  static const double holeImageWidthRatio = 0.85;
  static const double holeImageHeightRatio = 0.65;
  static const int pulseAnimationMs = 900;
  static const int scanAnimationMs = 2000;
  static const int consensusWindowSeconds = 5;
  static const int sideIntroSeconds = 3;
  static const int captureFlashMs = 80;
  static const int sideIntroFadeMs = 500;
  static const int switcherFadeMs = 300;
  static const int torchSwitcherFadeMs = 200;
}

/// Deduplicates `AnimatedSwitcher` children by widget [Key].
Widget animatedSwitcherDedupeLayout(
  Widget? current,
  List<Widget> previous,
) {
  final incomingKey = current?.key;
  final seen = <Key>{};
  if (incomingKey != null) seen.add(incomingKey);
  final filtered = <Widget>[];
  for (final w in previous) {
    final k = w.key;
    if (k == null) {
      filtered.add(w);
      continue;
    }
    if (seen.add(k)) filtered.add(w);
  }
  return Stack(
    alignment: Alignment.center,
    children: [
      ...filtered,
      if (current != null) current,
    ],
  );
}

/// Projects the visible hole/oval into camera-image pixel space via `BoxFit.cover`.
Rect computeOvalInImagePx({
  required Size? screenSize,
  required Size imageSize,
  required double holeWidth,
  required double holeHeight,
}) {
  if (screenSize == null || imageSize.isEmpty) return Rect.zero;

  final sw = screenSize.width;
  final sh = screenSize.height;
  final iw = imageSize.width;
  final ih = imageSize.height;

  final scale = (sw / iw) > (sh / ih) ? (sw / iw) : (sh / ih);
  final dx = (sw - iw * scale) / 2;
  final dy = (sh - ih * scale) / 2;

  final ovalCx = sw / 2;
  final ovalCy = sh / 2;

  return Rect.fromLTRB(
    (ovalCx - holeWidth / 2 - dx) / scale,
    (ovalCy - holeHeight / 2 - dy) / scale,
    (ovalCx + holeWidth / 2 - dx) / scale,
    (ovalCy + holeHeight / 2 - dy) / scale,
  );
}

/// Whether [snap] carries the minimum data required to leave the camera.
bool consensusHasMinimumData(OcrConsensusResult? snap) {
  if (snap == null) return false;
  final doc = snap.documentNumber.value?.trim() ?? '';
  final first = snap.firstName.value?.trim() ?? '';
  final last = snap.lastName.value?.trim() ?? '';
  return doc.isNotEmpty && (first.isNotEmpty || last.isNotEmpty);
}

/// Filters OCR text blocks to those that intersect the document hole.
RecognizedText filterBlocksInHole(
  RecognizedText recognized,
  Size imageSize,
) {
  final holeW = imageSize.width * CameraOverlayTuning.holeImageWidthRatio;
  final holeH = imageSize.height * CameraOverlayTuning.holeImageHeightRatio;
  final holeRect = Rect.fromCenter(
    center: Offset(imageSize.width / 2, imageSize.height / 2),
    width: holeW,
    height: holeH,
  );

  final filtered = recognized.blocks
      .where((block) => holeRect.overlaps(block.boundingBox))
      .toList();

  return RecognizedText(
    text: filtered.map((b) => b.text).join('\n'),
    blocks: filtered,
  );
}

/// Returns the initial guide string shown to the user before any frame.
String initialGuideText({required bool isFaceHole}) {
  return isFaceHole
      ? 'Posiciona tu rostro en el óvalo'
      : 'Encuadra el documento en el área';
}

/// Returns the loading message shown during capture.
String loadingMessage({required bool isLoading, required bool isBackSide}) {
  if (isLoading && !isBackSide) {
    return 'Anverso capturado\nAhora voltea el DNI';
  }
  return 'Capturando...';
}

/// Returns the new `perfectSince` timestamp, or `null` to keep the current one.
DateTime? perfectSinceOnRecover({
  required DateTime now,
  required DateTime? lastCaptureableAt,
}) {
  if (lastCaptureableAt == null) return now;
  final elapsed = now.difference(lastCaptureableAt).inMilliseconds;
  if (elapsed <= CameraOverlayTuning.gracePeriodMs) return null;
  return now;
}

/// Whether the grace window elapsed and `perfectSince` should be cleared.
bool shouldClearPerfectSince({
  required DateTime now,
  required DateTime? lastCaptureableAt,
}) {
  if (lastCaptureableAt == null) return false;
  return now.difference(lastCaptureableAt).inMilliseconds >
      CameraOverlayTuning.gracePeriodMs;
}

/// Outcome of a [BlinkLivenessTracker.update] call.
class BlinkUpdateResult {
  const BlinkUpdateResult({
    required this.fullyConfirmed,
  });

  final bool fullyConfirmed;
}

/// Tracks eye open→closed→open transitions to confirm liveness.
class BlinkLivenessTracker {
  BlinkLivenessTracker();

  bool _eyesWereClosed = false;
  int _blinkCount = 0;
  bool _detected = false;

  bool get isDetected => _detected;

  int get blinkCount => _blinkCount;

  bool get eyesWereClosed => _eyesWereClosed;

  BlinkUpdateResult update({
    required double? leftEyeOpen,
    required double? rightEyeOpen,
  }) {
    if (_detected) {
      return const BlinkUpdateResult(fullyConfirmed: false);
    }

    final left = leftEyeOpen ?? 1.0;
    final right = rightEyeOpen ?? 1.0;
    final bothClosed = left < CameraOverlayTuning.eyeClosedThreshold &&
        right < CameraOverlayTuning.eyeClosedThreshold;
    final bothOpen = left > CameraOverlayTuning.eyeOpenThreshold &&
        right > CameraOverlayTuning.eyeOpenThreshold;

    if (!_eyesWereClosed && bothClosed) {
      _eyesWereClosed = true;
    } else if (_eyesWereClosed && bothOpen) {
      _eyesWereClosed = false;
      _blinkCount++;
      if (_blinkCount >= CameraOverlayTuning.requiredBlinks) {
        _detected = true;
        return const BlinkUpdateResult(fullyConfirmed: true);
      }
    }

    return const BlinkUpdateResult(fullyConfirmed: false);
  }

  void reset() {
    _eyesWereClosed = false;
    _blinkCount = 0;
    _detected = false;
  }
}

/// Parses a `DD/MM/YYYY` date and returns it only when it is in the past.
DateTime? expirationIfPast(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw.trim());
  if (m == null) return null;
  final parsed = DateTime.tryParse(
    '${m.group(3)}-${m.group(2)}-${m.group(1)}',
  );
  if (parsed == null) return null;
  return parsed.isBefore(DateTime.now()) ? parsed : null;
}
