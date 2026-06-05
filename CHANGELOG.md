# Changelog

## 0.6.3 (bugfix)

Hotfix for "two-sided scan loses OCR" symptom reported against v0.6.x.

### Root cause

The package widget is destroyed and recreated when the host navigates from
the front step to the back step (Flutter's `switch` over enum steps does
NOT reuse state, even when the widget type is the same). The previous
`_accumulatedFields` is destroyed and the new back-side widget calls
`onSideChanged(isBackSide: true)` **without a seed** — so the back-side
accumulator starts blank.

When the back-side MRZ frames came partial, v0.6.1's `_buildMrzResultFromFields`
fallback to the vote map had nothing to fall back to (vote map also empty)
and the snapshot returned null names. The consumer then fell back to local
profile data, violating "OCR ALWAYS WINS".

### Fix — two new opt-in `DniCameraMask` parameters

**`onFrontSideOcrUpdated`** — callback emitted during front-side scanning
every time the internal `_accumulatedFields` learns a new field. Hosts
persist these values across the step transition (Bloc/Cubit/state holder).

**`frontSideFields`** — back-side widget receives the persisted fields and
the package seeds the back-side accumulator via
`onSideChanged(isBackSide: true, frontSideFields: ...)`.

Both parameters are **opt-in**. Existing consumers keep their behavior;
hosts that want correct two-sided scanning wire both.

### Consumer integration sketch

```dart
// Front step
DniCameraMask(
  isBackSide: false,
  onFrontSideOcrUpdated: (fields) {
    context.read<KycCubit>().rememberFrontSideOcr(fields);
  },
  onValidCapture: (file, _) => cubit.captureFront(file.path),
  controller: cameraController,
)

// Back step
DniCameraMask(
  isBackSide: true,
  frontSideFields: state.frontSideOcr,  // ← from your state holder
  onValidCapture: (file, consensus) =>
      cubit.captureBackWithConsensus(file.path, consensus: consensus!),
  controller: cameraController,
)
```

### Tests

498/498 pass (unchanged — the new params are inert in the existing test
scenarios). `flutter analyze` clean.

## 0.6.2 (bugfix)

Second hotfix on top of v0.6.1 — addresses BUG 1A (Spanish address anchor) and
BUG 2 (back-side motion blur) reported by JC against v0.6.0 (Engram obs #4669).
**No breaking API changes** — consumers bump SHA only.

### Bug 1A — `Dirección:` anchor now recognized

Real Peruvian electronic DNIs print **"Dirección:"** (Spanish accent) on the
reverse, NOT "Domicilio:". `AddressFieldStrategy` was DOMICILIO-only. Now
accepts `DOMICILIO`, `DOM`, `DOM.`, `DIRECCIÓN`, and `DIRECCION` as Strategy 1
anchors — both inline (`Dirección: ASENT.H15...`) and as a label on its own
line followed by the address.

The `DIRECCION` token stays in `kAddressNoiseDenylist` so it does not pollute
joined address strings — the anchor is detected on the raw line BEFORE the
noise filter runs.

### Bug 2 — Configurable MRZ lock threshold (motion blur mitigation)

`OcrConsensusAccumulator` lock-fires after 2 consecutive MRZ-valid frames
(~66ms at 30fps). For the electronic DNI back side, the underlying
`takePicture()` pipeline needs more stability time to deliver a sharp still.

New constructor parameter `mrzConsecutiveRequired` exposes the threshold:

```dart
// Default: 2 (backwards compatible — booklet DNI or front)
OcrConsensusAccumulator();
// Back side electronic DNI: 5 frames ≈ 165ms stability window
OcrConsensusAccumulator(mrzConsecutiveRequired: 5);
```

Host widgets can pick the right threshold per side. Consumers do NOT need to
change anything to keep the v0.6.x behavior.

### Tests

10 new regression tests:
- 4 for BUG 1A in `test/data/strategies/address_field_strategy_test.dart`.
- 6 for BUG 2 in `test/data/ocr_consensus_test.dart`.

**498/498 tests pass. `flutter analyze` clean (0 issues).**

## 0.6.1 (bugfix)

Hotfix for two pre-existing bugs in `OcrConsensusAccumulator` reported by JC
against v0.6.0. **No public API changes** — patch release, consumers bump SHA only.

### Bug 3A — `firstName` / `lastName` now fall back to the vote map

`_buildMrzResultFromFields` was asymmetric: `secondLastName` already fell back to
the text-OCR vote map when the MRZ buffer was null, but `firstName` and `lastName`
did not. A back-side MRZ frame with the names line garbled would erase the
front-side seed, leading to `null` names in the final snapshot. All MRZ-sourced
fields (`documentNumber`, `firstName`, `lastName`, `secondLastName`, `dateOfBirth`,
`expirationDate`) now consistently fall back to the vote map.

### Bug 3B — `lockFromMrzFields` now merges with the previous buffer

Each call to `lockFromMrzFields` used to **replace** the entire buffer. If frame 1
captured all fields cleanly and frame 2 had any field come `null` (e.g. ML Kit
dropped a character on the names line), the buffer would be overwritten with the
partial frame and the lock would fire on incomplete data. The buffer now merges
field-by-field — a new `null` does not erase a previously captured value.

### Tests

Three new regression tests in `test/data/ocr_consensus_test.dart`:
- BUG 3A: snapshot falls back to vote map for `firstName` / `lastName` when buffer is null.
- BUG 3B: `lockFromMrzFields` merges with previous buffer instead of overwriting.
- End-to-end: front seed + 2 back-side frames with partial MRZ → snapshot is complete.

488/488 tests pass. `flutter analyze` clean.

## 0.6.0 (breaking changes)

### Breaking changes

#### `OcrExtractedFields.logger` removed (global static → constructor injection)

**Before:**
```dart
OcrExtractedFields.logger = mySentryLogger;
```

**After:**
```dart
final extractor = OcrFieldExtractor(logger: mySentryLogger);
```

- `OcrExtractedFields.logger` static mutable field is removed.
- `OcrFieldExtractor` accepts `logger: OcrLogger` in its constructor (defaults to `NoOpOcrLogger`).
- `OcrExtractedFields.merge()` accepts an optional `logger:` parameter.
- `DniCameraController` accepts `logger: OcrLogger` in its constructor.
- Telemetry breadcrumbs are routed through the controller via `controller.emitBreadcrumb(...)`.

#### `DocumentValidationResult.borderColor` removed (domain → presentation)

**Before:**
```dart
final color = result.borderColor;  // Color from domain result
```

**After:**
```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';
final color = ValidationGateColors.colorFor(result.failingGate, theme);
```

- `DocumentValidationResult.borderColor` (`Color`) is removed.
- `failingGate` is now typed `ValidationGate?` (enum) instead of `String?`.
- New `ValidationGate` enum with values: `minBlocks`, `centering`, `fillHigh`, `fillLow`, `lineCount`, `tilt`.
- Each gate has a stable Sentry code via `gate.sentryCode`.
- New `ValidationGateColors.colorFor(ValidationGate?, KycTheme)` in the presentation layer.
- `DocumentValidationResult.evaluate(theme:)` — the `theme` parameter is now `@Deprecated` and silently ignored. Remove it at your convenience. It will be removed in v0.7.0.

#### `OcrConsensusBuilder` → `OcrConsensusAccumulator`

**Before:**
```dart
final builder = OcrConsensusBuilder();
```

**After:**
```dart
final accumulator = OcrConsensusAccumulator();
// OcrConsensusBuilder is a deprecated typedef alias — still compiles,
// but remove it before v0.7.0.
```

- `OcrConsensusBuilder` is `@Deprecated` and will be removed in v0.7.0.
- `OcrConsensusAccumulator` is the canonical class name.
- `DniCameraController.onSideChanged()` now owns the accumulator lifecycle.
  Pass `isBackSide: true` and optionally `frontSideFields:` to seed it.
- New `DniCameraController.recordOcrFrame(OcrExtractedFields)` — call per frame on back side.
- New `DniCameraController.snapshotConsensus()` — returns current `OcrConsensusResult?`.
- `DniCameraMask` no longer holds the accumulator directly.

### New APIs

- `ValidationGate` enum — compile-time exhaustive gate identification.
- `ValidationGateColors` — presentation helper mapping `ValidationGate?` to `Color`.
- `OcrConsensusAccumulator` — renamed accumulator with same behavior.
- `DniCameraController.emitBreadcrumb(category, message, {data})` — routes breadcrumbs through the injected logger.
- `DniCameraController.recordOcrFrame(fields)` → `bool` (consensus reached).
- `DniCameraController.snapshotConsensus()` → `OcrConsensusResult?`.

### Internal (non-breaking)

- Clean Architecture chapters 1–3 (file reorganization, strategy decomposition, controller/orchestrator extraction) already landed in v0.6.0 pre-releases.

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
