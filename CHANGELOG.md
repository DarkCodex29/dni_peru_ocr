# Changelog

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
