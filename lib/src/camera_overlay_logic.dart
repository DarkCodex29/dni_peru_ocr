import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Tuning constants shared by the camera overlay state machine.
///
/// Centralised here so future splits (`DniCameraMask` / `FaceCameraMask`) can
/// reuse them without circular references with the orchestrating widget.
class CameraOverlayTuning {
  const CameraOverlayTuning._();

  /// Length of the auto-capture countdown once the user holds the document
  /// (or face) inside the hole with all gates green.
  static const int autoCaptureMs = 1500;

  /// Grace window during which a brief "captureable → not captureable"
  /// transition is tolerated without resetting the captureable timestamp.
  /// Avoids flicker on noisy frames between two otherwise stable readings.
  static const int gracePeriodMs = 600;

  /// Minimum consecutive frames where block count is stable before a
  /// document capture is allowed. Prevents capturing while the user is
  /// still moving the card.
  static const int minStableFrames = 2;

  /// Number of full blinks (open → closed → open transitions) required
  /// to consider face liveness confirmed.
  static const int requiredBlinks = 1;

  /// Eye-open probability above which an eye is considered open.
  static const double eyeOpenThreshold = 0.5;

  /// Eye-open probability below which an eye is considered closed.
  static const double eyeClosedThreshold = 0.3;

  /// Timeout after which the manual-capture fallback button appears so
  /// users can force a capture if auto-detection never converges.
  static const int manualFallbackMs = 15000;

  /// Horizontal fraction of the camera image considered "inside the hole"
  /// when filtering OCR blocks. 85% is empirically tuned for Peruvian DNI
  /// dimensions framed centrally in portrait orientation.
  static const double holeImageWidthRatio = 0.85;

  /// Vertical fraction of the camera image considered "inside the hole".
  static const double holeImageHeightRatio = 0.65;

  /// Animation duration of the pulse used to highlight the capture ring.
  static const int pulseAnimationMs = 900;

  /// Animation duration of the scan line traversing the hole.
  static const int scanAnimationMs = 2000;

  /// Window during which back-side OCR consensus votes are accumulated
  /// before a manual fallback decision is considered.
  static const int consensusWindowSeconds = 5;

  /// Delay before the side-intro ribbon hides itself once the user moves
  /// from the front to the back side of the document.
  static const int sideIntroSeconds = 3;

  /// Duration of the capture-flash white overlay shown right after the
  /// shutter fires. Tuned to feel snappy without being subliminal.
  static const int captureFlashMs = 80;

  /// Fade duration of the side-intro ribbon when it appears or disappears.
  static const int sideIntroFadeMs = 500;

  /// Cross-fade duration of the auto-switcher used by the manual-fallback
  /// pill and the guide text banner.
  static const int switcherFadeMs = 300;

  /// Cross-fade duration of the auto-switcher used by the torch button.
  static const int torchSwitcherFadeMs = 200;
}

/// Deduplicates `AnimatedSwitcher` children by widget [Key] to avoid
/// "Duplicate keys" crashes during rapid step transitions.
///
/// Bug context: in fast A → B → A flips, Flutter's `AnimatedSwitcher` can
/// hold both the outgoing and incoming child with the same key while the
/// transition completes. This builder keeps only the first occurrence of
/// each keyed widget, plus all keyless widgets.
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

/// Projects the visible hole/oval (in screen dp) into camera-image pixel
/// space using a `BoxFit.cover` model — the same transform `CameraPreview`
/// applies.
///
/// Returns `Rect.zero` if the screen size is unknown or the image is empty.
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

/// Back-side capture requires at minimum the document number plus either
/// the surname or the given names. Without either, the confirmation screen
/// would render an empty form — better to keep the user on the camera.
bool consensusHasMinimumData(OcrConsensusResult? snap) {
  if (snap == null) return false;
  final doc = snap.documentNumber.value?.trim() ?? '';
  final first = snap.firstName.value?.trim() ?? '';
  final last = snap.lastName.value?.trim() ?? '';
  return doc.isNotEmpty && (first.isNotEmpty || last.isNotEmpty);
}

/// Filters OCR text blocks down to those that intersect the document hole
/// rectangle centred in the camera image.
///
/// The hole is computed as a fraction of [imageSize] using
/// [CameraOverlayTuning.holeImageWidthRatio] and
/// [CameraOverlayTuning.holeImageHeightRatio]. Returns a new
/// [RecognizedText] whose `blocks` only contain the surviving entries and
/// whose `text` is the joined block text in document order.
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

/// Returns the initial guide string shown to the user before any frame has
/// been processed. Depends only on whether the hole is rectangular
/// (document) or rounded (face/selfie).
String initialGuideText({required bool isFaceHole}) {
  return isFaceHole
      ? 'Posiciona tu rostro en el óvalo'
      : 'Encuadra el documento en el área';
}

/// Returns the message displayed while the camera is capturing. Front-side
/// capture shows a "now flip the card" hint; back-side capture remains
/// silent until the verification step takes over.
String loadingMessage({required bool isLoading, required bool isBackSide}) {
  if (isLoading && !isBackSide) {
    return 'Anverso capturado\nAhora voltea el DNI';
  }
  return 'Capturando...';
}

/// Decides whether a captureable transition should reset the `perfectSince`
/// timestamp. Returns:
///
///   - `null` when no transition happened (caller does nothing),
///   - the new timestamp to assign to `perfectSince` when a fresh
///     captureable window opens outside of the grace period.
///
/// `lastCaptureableAt` is the previous moment at which the user briefly
/// dropped out of captureable. Within
/// [CameraOverlayTuning.gracePeriodMs] of that timestamp, the original
/// `perfectSince` value is preserved (returns `null`).
DateTime? perfectSinceOnRecover({
  required DateTime now,
  required DateTime? lastCaptureableAt,
}) {
  if (lastCaptureableAt == null) return now;
  final elapsed = now.difference(lastCaptureableAt).inMilliseconds;
  if (elapsed <= CameraOverlayTuning.gracePeriodMs) return null;
  return now;
}

/// Returns true when the grace window has elapsed since the user last
/// dropped out of captureable, meaning `perfectSince` should be cleared.
bool shouldClearPerfectSince({
  required DateTime now,
  required DateTime? lastCaptureableAt,
}) {
  if (lastCaptureableAt == null) return false;
  return now.difference(lastCaptureableAt).inMilliseconds >
      CameraOverlayTuning.gracePeriodMs;
}

/// Outcome of a single [BlinkLivenessTracker.update] call.
class BlinkUpdateResult {
  const BlinkUpdateResult({
    required this.fullyConfirmed,
  });

  /// `true` only on the frame where the cumulative blink count reaches
  /// [CameraOverlayTuning.requiredBlinks]. Callers typically use this to
  /// trigger a haptic confirmation.
  final bool fullyConfirmed;
}

/// Tracks eye open→closed→open transitions to confirm liveness.
///
/// A static photo of a face cannot trigger this tracker because the
/// reported eye-open probabilities never cross the open/closed thresholds
/// dynamically — they remain locked at the photo's frozen values.
///
/// Thresholds are read from [CameraOverlayTuning.eyeOpenThreshold] and
/// [CameraOverlayTuning.eyeClosedThreshold].
class BlinkLivenessTracker {
  BlinkLivenessTracker();

  bool _eyesWereClosed = false;
  int _blinkCount = 0;
  bool _detected = false;

  /// `true` once enough complete blinks have been observed.
  bool get isDetected => _detected;

  /// Number of complete open→closed→open cycles observed so far.
  int get blinkCount => _blinkCount;

  /// Whether the tracker is currently in the "eyes closed" state, waiting
  /// for them to open before counting a full blink.
  bool get eyesWereClosed => _eyesWereClosed;

  /// Feeds one frame's eye-open probabilities into the state machine.
  ///
  /// `null` probabilities are treated as "open" (1.0), matching ML Kit's
  /// behaviour when classification cannot determine eye state confidently.
  ///
  /// Returns a [BlinkUpdateResult] describing what happened this frame.
  /// No-op (returns a non-confirmed result) once [isDetected] is `true`.
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

  /// Clears the tracker back to its initial state. Call when restarting
  /// the capture flow or when the user retries.
  void reset() {
    _eyesWereClosed = false;
    _blinkCount = 0;
    _detected = false;
  }
}

/// Parses an MRZ-extracted `DD/MM/YYYY` date and returns it only when it
/// represents a past moment (i.e. the document is expired).
///
/// Returns `null` for null/empty input, unparseable formats, or any date
/// that is still in the future.
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
