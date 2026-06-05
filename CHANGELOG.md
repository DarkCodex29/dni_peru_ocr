# Changelog

## 0.5.0

- `KycTheme.darkDefaults()` — OLED-tuned dark variant.
- `KycTheme.fromMaterialTheme(ThemeData)` — bridges Material 3 ColorScheme onto the KYC slots.
- `KycTheme.copyWith(...)` — partial overrides without redefining the whole theme.
- `DniCameraMask`: flash toggle moved next to the manual capture button (bottom-right) instead of top-right, so it sits closer to the primary CTA when the manual fallback panel surfaces.
- All `debugPrint` calls are guarded with `kDebugMode` so release builds skip the string interpolation cost.

## 0.4.0

- `DniCameraMask` — full DNI scanning widget. Renders the document hole, animated scan line, capture countdown, manual fallback panel, side-intro ribbon and the G.1 telemetry overlay (debug builds only). Hosts the MRZ + consensus pipeline.
- `DocumentValidator` — geometric + OCR-aware framing gate. Now takes a `KycTheme` so border colors stay configurable per app.
- `UserVerificationData` — small value type with `matchesText` for OCR cross-checks.
- `DetectorLifecycle` — deterministic `Completer`-based drain that prevents SIGSEGV when closing ML Kit detectors mid-inference.

## 0.3.0

- `KycTheme` + `KycThemeProvider` — theming abstraction so the scanner widgets can be styled without leaking host-app color palettes. `KycTheme.defaults()` ships neutral defaults that you can override per app.
- `CameraOverlayTuning` — 13 named timing/animation/threshold constants previously hardcoded inside the camera widget (autoCaptureMs, gracePeriodMs, eye thresholds, hole ratios, animation durations, fade durations).
- `BlinkLivenessTracker` — pure state machine for face liveness (open → closed → open transitions). Detects static-photo spoofing because frozen probabilities never cross thresholds dynamically. Now reusable outside the camera widget.
- Pure helpers extracted from the camera state class: `animatedSwitcherDedupeLayout`, `filterBlocksInHole`, `computeOvalInImagePx`, `initialGuideText`, `loadingMessage`, `consensusHasMinimumData`, `perfectSinceOnRecover`, `shouldClearPerfectSince`, `expirationIfPast`.

## 0.2.0

- Added camera-side helpers: `TiltCalculator`, `ImageQualityGate`, `KycImageUtils`, `InputImageConverter`, `BreadcrumbThrottle`.

## 0.1.0

- Initial release.
- `OcrFieldNormalizer` — tilde-aware name denoise (`Ñ` recovery from `NXX` ML Kit corruption) and display normalization.
- `OcrFieldExtractor` — multi-strategy field extraction from `RecognizedText` with noise filtering, label denylist for Peruvian DNI vocabulary, and structural anchor heuristic.
- `OcrConsensusBuilder` — temporal voting across frames with MRZ checksum lock and display-value preservation.
- `StringSimilarity` — Wagner-Fischer Levenshtein for fuzzy OCR comparison.
- `OcrLogger` — pluggable logging interface; default no-op implementation.
