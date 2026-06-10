# Changelog

## 0.17.0

### Added
- `DniCaptureMode` enum (`auto` | `manual`) and `DniScanner.captureMode`
  parameter. In `manual` mode the scanner keeps hunting OCR fields (field
  consensus and RENIEC lookup still run) but the picture is only taken when
  the user taps the new capture button. The button turns green when the
  hunt state machine reports the frame is stable enough to capture, and
  shows a progress indicator while capturing. The flash toggle moves to the
  side of the capture button in manual mode. Default remains
  `DniCaptureMode.auto` (no behavior change for existing consumers).

## 0.16.0

### Changed (BREAKING)
- `DniData` identity fields (`nombres`, `apellidoPaterno`,
  `apellidoMaterno`, `nombreCompleto`) are now `String?` instead of
  `String`. A `null` value means "not selected in `DniFields`" or "not
  returned by the lookup source", which consumers can distinguish from
  an empty string returned by a backend.
- `DniDataMerger` now returns `null` instead of `''` for fields the
  consumer did not request via `DniFields`.

### Migration
- Consumers that called `data.nombres.trim()` (etc.) must guard against
  `null`: `(data.nombres ?? '').trim()`.

## 0.15.2

### Changed
- `DniScanner` now scales `HuntStateMachine.minFieldsForFastAdvance`
  based on the consumer's `DniFields.length`, so smaller field
  selections (e.g. `DniFields.kyc()` = 7 fields) hit the fast-advance
  threshold instead of being stuck on the 12-field default.
- Telemetry log now reports `filled/<selectedCount>` instead of the
  hardcoded `filled/19`.

## 0.15.1

### Added
- `OcrConsensusResult.fromHunt(HuntResult)` factory — bridges
  `DniScanner` single-side output (`HuntResult`) to consumers that still
  expect an `OcrConsensusResult` downstream.

## 0.15.0

### Added
- `DniScanner` single-side mode: pass `isBackSide: false` to scan only
  the front, `isBackSide: true` to scan only the back. The scanner emits
  the new `DniSideScanResult` via `onSideCaptured`. Two-sided mode
  (legacy default with `isBackSide: null`) remains unchanged.
- `DniSideScanResult` — payload for single-side captures (`photo`,
  `isBackSide`, `hunt`, `reniecData`).
- `HuntStateMachine` accepts `initialPhase`, so single-side mode can
  start directly at `waitingBack`.

### Notes
- Single-side mode enables consumers like Inclub to keep step-by-step
  flows (with intermediate backend uploads between sides) while still
  using the bundled scanner UI.

## 0.14.0

### Added
- `DniScanner` now supports `lookupService`, `lookupTimeout` and
  `onDniReady`. Fires the RENIEC lookup automatically when the front
  capture exposes a `documentNumber` and bundles the resolved
  `DniData` into `DniScanResult.reniecData`.

### Changed
- `DniCameraMask.fields` defaults to `DniFields.kyc()` when omitted.
- `DniCameraMask` constructor is no longer `const` because `fields`
  defaults to a non-const `DniFields.kyc()` instance.

### Fixed
- **Premature front-side capture**: `CaptureDecider` is now side-aware.
  Previously, the auto-capture path required `HuntResult.isComplete`
  (all 6 fixed fields including MRZ-only ones like `expirationDate`),
  which could never become `true` while the user was still on the front.
  The widget then fell back to framing-only gates and captured blurry
  front shots before the OCR pipeline had consensus on the front-printed
  fields.
- The decider now requires:
  - Front side: every requested `DniField` that is physically printed on the
    front of the DNI (documentNumber, names, sex, nationality, organDonor,
    votingGroup, stateCivil) must be consensuated.
  - Back side: full `HuntResult.isComplete` (unchanged behavior).

### Added
- `HuntResult.requiredFields` — propagates the consumer's `DniFields`
  selection so `isComplete` honors it.
- `HuntResult.isFrontReady` — new front-only gate, intersects the requested
  fields with `HuntResult.frontPrintedFields`.
- `HuntResult.frontPrintedFields` — public constant set listing every
  `DniField` physically printed on the front of the DNI Modelo 2020.
- `CaptureDecider.decide` now accepts `isBackSide` (defaults to `false`
  for source compatibility).

### Notes
- Backwards-compatible: hosts that don't pass `fields` keep the legacy
  triplet gate (documentNumber + lastName + firstName) on the front
  instead of capturing on framing alone.

## 0.13.1

### Added
- `ValidationGate.sideMismatch` — new gate emitted when the user is showing
  the wrong side of the DNI (front while `isBackSide: true`, or back while
  `isBackSide: false`).
- `DocumentValidator.evaluate` now rejects capture and shows
  "Estás mostrando el reverso. Voltea al frente del DNI." (or the inverse)
  using the existing `DocumentSideDetector` anchors (CUI, REPÚBLICA DEL PERÚ,
  DONACIÓN DE ÓRGANOS, CONSTANCIA DE SUFRAGIO). Works on Modelo 2020 AND
  the azul booklet (DNI viejo).

### Notes
- Prevents capturing the same side twice (e.g. user showed the back twice and
  the back's MRZ filled both anverso and reverso slots).
- No public API change. Existing consumers automatically benefit.

## 0.13.0

### Added
- `InMemoryDniCache` — public convenience implementation of `DniCache` backed
  by a `Map<String, DniData>`. Useful for tests, demos, and consumer apps that
  do not need persistence across process restarts. For production cross-session
  caching, consumers can still implement `DniCache` backed by Hive,
  `shared_preferences`, sqflite, etc.

### Notes
- Additive only. No public API change beyond the new export.
- The example app used to ship its own `InMemoryDniCache` copy; that file was
  removed and the example now consumes the library's implementation.

## 0.12.1

### Changed
- `DniCameraMask` now uses shared `ScannerHint` and `ScannerFlashToggle` widgets
  (same as `DniScanner`). Hint pill appears below the document frame; flash
  toggle is centered at the bottom with high-contrast black background, white
  border, and shadow.
- Flash toggle icon size increased to 22 (was 20) and padding to 12 (was 10)
  to meet Material accessibility 44×44 touch target minimum.
- Removed legacy `_GuideTextBanner` and `_FlashToggle` from
  `_camera_overlay_widgets.dart` — single source of truth.

### Notes
- No public API change.
- Consumers using `DniCameraMask` (Inclub, etc.) now see the same in-camera
  chrome that `DniScanner` already used in the example app: orange gradient
  banner, dark hint pill, accessible flash toggle.

## 0.12.0

### Changed
- **Banner redesign in `DniCameraMask`**: the front→back transition now shows
  the same orange gradient banner used by `DniScanner` (Material Orange 600 → 700)
  with rotating flip icon and haptic feedback. Previously `DniCameraMask` had its
  own gray-translucent `_SideIntroRibbon` that consumers reported as nearly invisible.
- Banner widget extracted to `_shared_scan_widgets.dart` so both `DniScanner` and
  `DniCameraMask` render the same `FlipDocumentBanner`. Single source of truth for
  the in-camera UX.
- Banner text: `"Voltee el documento"` (was `"Anverso listo — ahora voltea el DNI"`).

### Notes
- No public API change. The `_SideIntroRibbon` was already a private widget;
  consumers that embed `DniCameraMask` see the new banner automatically.
- The orange gradient is hardcoded (not theme-driven) to ensure all consumers
  get the same protagonist visual without per-app configuration.

## 0.11.2

### Fixed
- `_SideIntroRibbon` ("Voltee el documento" banner) now activates correctly when
  `DniCameraMask` is constructed directly with `isBackSide: true`, not only when
  the same widget instance transitions from front to back via `didUpdateWidget`.
  This unblocks integrations like Inclub mobile app where each KYC step builds
  a fresh `DniCameraMask` instance and the previous code path never triggered.

### Notes
- No public API change. Existing consumers reusing one widget across front/back
  see identical behavior. New behavior only fires for consumers constructing a
  back-side widget from scratch.

## 0.11.1

### Changed
- Moved `dio` from `dev_dependencies` to `dependencies` to comply with pub.dev publication rules.
  Packages imported from `lib/` must be declared as direct dependencies.

### Removed
- Removed `analysis_options.yaml` suppression of `depend_on_referenced_packages` that was masking the
  dio placement issue.

### Notes
- No functional changes. v0.11.0 consumers see identical behavior.
- Consumers of `dni_peru_ocr` now transitively load `dio` as a runtime dependency, even when not using
  `DioDniHttpClient`. This is a tradeoff against the original v0.9.0 design promise of "OCR-only consumers
  pay no dio cost". Pub.dev compliance is non-negotiable; the bundle impact is ~150KB which is negligible
  compared to ML Kit dependencies the library already requires.

## 0.11.0

### Added
- `DniField` enum — 19 public values mapped 1:1 to ExtractedFields properties.
- `DniFields` immutable wrapper with factories `required({...})`, `minimal()`, `kyc()`, `full()` and value-based equality.
- `FieldHunter.standard()` accepts optional `DniFields? fields` parameter. When provided, only extractors that produce at least one selected field are instantiated, reducing CPU and battery usage.
- `DniScanner` and `DniCameraMask` widgets accept optional `fields` parameter.
- `DniDataMerger.merge()` accepts optional `fields` parameter; non-selected fields are null in merged output even if RENIEC returned values.
- Threshold scaling: `HuntStateMachine.minFieldsForFastAdvance` scales proportionally as `max(3, (selectedCount * 0.75).round())` clamped to 14.

### Changed
- Library version bumped from 0.10.0 to 0.11.0.

### Notes
- All field selection APIs are optional. Consumers omitting the `fields` parameter see identical v0.10.0 behavior.
- Multi-field extractors (MRZ, dates, ubigeo, surname) run if at least one of their produced fields is in the selected set.
- The `DniCameraMask` legacy `OcrConsensusAccumulator` pipeline is not filtered by `fields`; only the FieldHunter path honors selection.

## 0.10.0

### Added
- `ReliableDniPipeline` — internal orchestrator that fires lookup once per scan session when DNI consensus is reached, with a configurable 1500ms timeout and silent OCR fallback on failures.
- `DniDataMerger` — internal pure function applying RENIEC-prevails rules with whitespace defense; DNI number always preserved from OCR consensus.
- `DniCameraMask` and `DniCameraController` now accept optional `lookupService` and `onDniReady` parameters. When provided, the library automatically wires the lookup pipeline; consumers receive reliable DNI data through `onDniReady` without writing any wiring code.
- `KycTheme` gains `gradientStart` and `gradientEnd` color tokens for branded UI accents.

### Changed
- `_SideIntroRibbon` (flip-card hint banner) redesigned with gradient background, slide-in animation, rotating icon, and haptic feedback on mount.
- `_FlashToggle` (camera flash control) redesigned with larger touch target, higher contrast, and tactile feedback on tap.
- Library version bumped from 0.9.0 to 0.10.0.

### Notes
- Lookup remains fully optional — consumers omitting the new parameters continue to use the OCR-only flow from v0.9.0 unchanged.
- `ReliableDniPipeline` and `DniDataMerger` are internal and never exported. They are wired automatically when `lookupService` is provided.
- `rawSource` field on `DniData` is never set by the merger, preserving the silent merge contract: consumers cannot distinguish merged from OCR-only data via the API surface.

## 0.9.0

### Added
- `DniLookupService` abstract contract for plugging external DNI data sources.
- `DniData` common model with required fields (`dni`, `nombres`, `apellidoPaterno`, `apellidoMaterno`, `nombreCompleto`) and optional fields (`ubigeo`, `departamento`, `provincia`, `distrito`, `rawSource`, opt-in `raw` map).
- `DniLookupResult` sealed class with 6 variants: `DniLookupSuccess`, `DniLookupNotFound`, `DniLookupRateLimited`, `DniLookupNetworkError`, `DniLookupInvalidToken`, `DniLookupServerError`.
- `ApisPeruLookupService` — built-in adapter for `dniruc.apisperu.com` with defensive handling of plain-text 500 invalid-token responses.
- `ReniecSunatLookupService` — built-in adapter for self-hosted RENIEC/SUNAT backends with configurable `baseUrl` and optional `extraHeaders`.
- `DniHttpClient` abstract HTTP contract + `DioDniHttpClient` adapter (consumer provides configured `Dio` instance).
- `CachingDniLookupService` decorator — cache-aside pattern with in-memory TTL tracking; consumer provides `DniCache` implementation.
- `FallbackDniLookupService` decorator — ordered service chain with configurable retry predicate; stops on `InvalidToken` by default.
- `DniCache` abstract contract for consumer-implemented storage.
- `DniHttpResponse` value type carrying HTTP status code and response body.
- `DniLookupRetryPredicate` typedef for `FallbackDniLookupService` customization.

### Changed
- Library version bumped from 0.7.3 to 0.9.0 to reflect the new lookup capability.

### Notes
- `dio` is a `dev_dependency`. Library consumers do not pay the bundle cost unless they instantiate `DioDniHttpClient`.
- The lookup feature is fully optional; OCR-only consumers compile and run identically to v0.7.x.
- No breaking changes to v0.7.x public API. All existing exports remain intact.
- `analysis_options.yaml` suppresses `depend_on_referenced_packages` info-level lint as a documented short-term tradeoff.

## 0.7.3 - 2026-06-06

### Added

- Runnable example app under `example/` demonstrating the full capture flow:
  Home → Scan (front + back with `frontSideFields` seeding) → Result.
- `ErrorScreen` in the example covering document expiration, capture cancellation,
  camera permission denial, and camera initialization failure paths.
- Confidence-graded `FieldCard` and `ConfidenceBadge` widgets in the example
  showing how to render `OcrConsensusResult` to end users.
- CI step that runs `flutter analyze --fatal-warnings` against the example so
  future API changes cannot silently break the demo.

### Changed

- Root README now points to the example app as the recommended starting point
  for new consumers.

## 0.7.2 - 2026-06-06

### Changed (BREAKING for callback shape)

- `DniCameraController` constructor parameter `onValidCapture` now has type
  `void Function(XFile file, OcrConsensusResult? consensus)` instead of
  `void Function(dynamic file, dynamic consensus)`.
- `DniCameraController.onCaptureDelivered` named parameters `file` and
  `consensus` are now typed `XFile` and `OcrConsensusResult?` respectively.
- Consumers that destructure the callback arguments with explicit dynamic types
  will get a compile error and must update their callback signature. Consumers
  using inferred-parameter lambdas (`(_, __) {}`) are unaffected.
- **Patch version despite the shape change**: this package has never been
  published to pub.dev, and the only known consumer is InClub (controlled by
  the same author). v0.8.0 is reserved for the upcoming internal refactor.

### Refactored (internal)

- Overlay widgets in `_camera_overlay_widgets.dart` renamed to library-private
  (`_ManualCapturePanel`, `_SideIntroRibbon`, `_G1TelemetryOverlay`,
  `_GuideTextBanner`, `_DataMatchIndicator`, `_FlashToggle`) and converted to
  a `part` file of `dni_camera_mask.dart` to enforce intra-library privacy.
- `_DniCameraMaskState._processDocument` parameter `inputImage` typed from
  `dynamic` to `InputImage` — eliminates an implicit dynamic call into ML Kit.

### Removed

- Dead `&& true` guard on the `kDebugMode` branch in `DniCameraMask.build`
  (the telemetry overlay was always rendered in debug mode; the guard was a
  stale boolean from early development).

## 0.7.1 - 2026-06-06

### Changed

- Applied `dart format` across all 25 library and test files (no logic changes).
- Loosened `google_mlkit_face_detection` constraint from exact pin `0.13.2` to
  caret `^0.13.2`, clearing the `dart pub publish --dry-run` warning.
- Added `topics: [ocr, flutter, identity, peru, mrz]` to `pubspec.yaml` for
  pub.dev discoverability.
- Added explicit `platforms: android / ios` declaration to `pubspec.yaml`.
- Fixed 8 unresolved dartdoc cross-references across 5 library files.
- Updated README installation section: `dni_peru_ocr: ^0.7.1` (pub.dev) is now
  the primary snippet; `git:` syntax moved to a secondary "Install from source"
  subsection.

## 0.7.0 (breaking — deprecated alias removal + ubigeo feature)

Closes every follow-up item identified by the v0.6.x judgment-day audit.
Breaking surface is intentionally small; the v0.6.x APIs we removed were
already marked `@Deprecated` since v0.6.0–v0.6.4.

### Breaking changes

#### 1. `OcrConsensusBuilder` typedef removed

The deprecated alias on top of `OcrConsensusAccumulator` was kept for
in-place migration across v0.6.x. It is now gone — replace any remaining
usage with `OcrConsensusAccumulator` directly. Behaviour is identical.

#### 2. `OcrFieldExtractor.extractStatic` removed

The static alias for `OcrFieldExtractor.extract` is gone. The two names
always referred to the same logic; the alias only existed to soften the
v0.6.0 migration.

#### 3. `DocumentValidationResult.tiltCalculator` is now a constructor parameter

The static mutable test seam:

```dart
DocumentValidationResult.tiltCalculator = (_) => 20.0;
final r = DocumentValidationResult.evaluate(...);
```

is replaced by an optional named parameter on `evaluate()`:

```dart
final r = DocumentValidationResult.evaluate(
  recognizedText: text,
  imageSize: size,
  tiltCalculator: (_) => 20.0, // optional, defaults to computeMedianTiltDegrees
);
```

Defaults to `computeMedianTiltDegrees` so production callers do not need
to change anything. Tests that previously assigned to the static field
must pass the function as a named argument instead. This eliminates the
last global mutable static in the package surface.

#### 4. `DocumentValidationResult.evaluate(theme:)` removed

The `theme` parameter on `evaluate()` had been silently ignored since
v0.6.4 (it was only used by the removed `borderColor` field). The
parameter is now gone — drop it from the call site.

### Non-breaking improvements

#### 5. Three new optional fields on `OcrExtractedFields`

`department`, `province`, `district` are populated by `AddressFieldStrategy`
when the back-side OCR exposes the `DEPARTAMENTO/PROVINCIA/DISTRITO` line.
Handles three real-world shapes:

- `ANCASH/SANTA/CHIMBOTE` → positional `[department, province, district]`
- `/CALLAO/VENTANILLA` → `department + district`, province null
  (RENIEC convention for constitutional provinces)
- `LIMA/LIMA/VILLA MARIA DEL TRIUNFO` → multi-word district preserved

Consumers can read these fields directly without parsing the slash line
themselves. All three default to `null` when the line is missing.

#### 6. Name vote consolidation by strict prefix containment

When the consensus accumulator has votes like
`{lastName: MORENO} x1` and `{lastName: MORENO ALEMAN} x1`, the snapshot
now consolidates them: the longer variant wins and both votes count
toward its confidence. Uses **strict prefix containment** (no fuzzy
matching) so that `JUAN` and `JOSE` stay independent — fuzzy matching on
short names is too risky.

This is the same family of fix that v0.6.8 introduced for address, but
limited to prefix matches because name fields are short and high-signal.

#### 7. Address `locked` flag requires ≥ 2 votes

Single-vote address buckets cannot reach `OcrFieldResult.locked = true`
anymore — at least two corroborating frames are required. The displayed
value is unaffected (still emitted from the first vote), only the
`locked` flag is gated. Prevents premature lock on noisy single-frame
captures.

### Tests

7 new regression tests across `ocr_consensus_test.dart`,
`address_field_strategy_test.dart`, and `dni_camera_mask_widget_test.dart`:

- Name-prefix consolidation (3 cases).
- Ubigeo extraction for 3-part / 2-part / multi-word / absent variants
  (4 cases).
- Property-based order independence: shuffle 5 address votes 30× with
  different seeds, same winner every run.
- Widget-level E2E: `DniCameraMask.isBackSide: false → true` rebuild
  propagates the flag to the inner `DniCameraController` (regression
  guard for the v0.6.4 stale-flag bug).

**529/529 tests pass.** `flutter analyze` clean.

### Consumer impact for InClub

No code changes required. InClub does not use any of the four removed
APIs (`OcrConsensusBuilder`, `extractStatic`, the static `tiltCalculator`,
or `evaluate(theme:)`). Bump the SHA only.

## 0.6.10 (docs)

Documentation pass over the public surface and the most-touched internals.

### What changed

Production code is unmodified. The pass replaces ad-hoc bitácora comments
(`obs #...`, `BUG ...`, `v0.6.x hotfix`, reporter names) with DartDoc that
documents:

- Intent and role of each public class.
- SOLID principles applied (SRP, OCP, DIP) where relevant.
- Design patterns (Strategy, Accumulator, State holder injection).
- Invariants and lifecycle expectations.
- Empirical calibration values (e.g. `blurThreshold`, `_maxTiltDegrees`)
  with the reasoning that drove them, separated from the bug-tracking
  history that lives in git / Engram.

Files touched:

- `lib/src/data/ocr_consensus.dart`
- `lib/src/data/address_noise_filter.dart`
- `lib/src/data/strategies/address_field_strategy.dart`
- `lib/src/presentation/document_validator.dart`
- `lib/src/presentation/image_quality_gate.dart`
- `lib/src/presentation/controllers/dni_camera_controller.dart`
- `lib/src/presentation/widgets/dni_camera_mask.dart`

Bug-tracking metadata that was in the source moved to git log and to the
Engram observations linked from the `CHANGELOG.md` entries — the source
now talks about the *what* and the *why*, not the *when*.

### Consumer impact

No public API changes. No behaviour changes. Patch release. Bump SHA only.

**521/521 tests pass.** `flutter analyze` clean.

## 0.6.9 (polish + test hygiene)

Two non-breaking polish items from the judgment-day audit (Engram obs #4688):

### 1. Per-field MRZ source tag in logs

`OcrExtractedFields.toString()` was tagging every field with `[MRZ]` when
the accumulator was MRZ-sourced — including the address, which the MRZ
NEVER carries. Cosmetic but misleading during debug.

Fix: only fields the MRZ actually emits (`documentNumber`, paternal /
maternal surnames, given names, birth date, sex, expiration, nationality)
carry the tag now. Address and any future free-text field stay untagged.

### 2. Global `setUp` reset for `tiltCalculator` test seam

`DocumentValidationResult.tiltCalculator` is a static mutable seam used
only by tests. Per-test `addTearDown` already cleaned it up, but if a
test crashed BEFORE the tearDown registered, the value leaked to every
subsequent test. Added a global `setUp` reset in both files that touch
the seam — defensive belt-and-suspenders against test contamination.

(The seam itself is the v0.6.0 antipattern survivor `tiltCalculator` —
will be replaced with constructor injection in v0.7.0.)

### Tests

2 new tests in `test/data/ocr_field_extractor_test.dart`:
- MRZ-sourced fields tagged, address untagged.
- Non-MRZ accumulator: no tags at all.

**521/521 tests pass.** `flutter analyze` clean.

### Consumer impact

No public API changes. Patch release. Bump SHA only.

## 0.6.8 (bugfix)

Address vote consolidation across OCR micro-variants. Reported by JC against
v0.6.7: log showed `MILAGRO` across frames, UI showed `MLAGRO` (missing `I`).

### Root cause

ML Kit emits the same DNI address in many micro-variants across frames
because each frame has slightly different OCR noise:

| Frame | OCR output |
|---|---|
| 1 | `ASENT H15 DE ABRIL CALLE EL MILAGRO` |
| 2 | `ASENT H15 DE ABRIL CALLE EL MILAGRO MZ` |
| 3 | `ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19` |
| 4 | `ASENT H15 DE ABRIL CALLE EL MLAGRO MZ.B LT.19` |

The previous `_voteResult` gave each variant its own bucket, so a
`reduce(max)` over single-vote buckets returned a non-deterministic winner
— whichever variant Dart's `Map.entries` iteration happened to encounter
last. In JC's case the corrupted `MLAGRO` variant kept winning.

### Fix

Address voting now consolidates near-duplicate variants:

1. Sort buckets by string length descending.
2. For each bucket starting from the longest, absorb every shorter bucket
   that is either:
   - A whitespace+dot-collapsed PREFIX of the longer string, OR
   - ≥ 80% Levenshtein-similar to the longer string.
3. The longest string in each consolidated group wins; its absorbed votes
   sum.
4. The group with the highest combined vote count wins.

This guarantees deterministic, monotonically-preferring-completeness
behaviour:

| Scenario | Winner (v0.6.8) |
|---|---|
| Progressive completion across frames | The longest variant |
| 3× `MILAGRO` + 1× `MLAGRO` | `MILAGRO` (3-vote group beats 1-vote) |
| 5 different micro-variants, all 1 vote | The longest |
| Two unrelated addresses (rare) | The majority — no false merge |

Non-address fields (`firstName`, `lastName`, `secondLastName`,
`documentNumber`) keep the original strict equality voting. Only `address`
needed this looser policy because its content is free-text and ML Kit OCR
of the back-side stub is the noisiest signal in the pipeline.

### Tests

4 new regression tests in `test/data/ocr_consensus_test.dart`:

1. `progressive completion: shorter variants merge into the longest`
2. `OCR glitch in one frame is outvoted by the well-read majority`
3. `all variants 1-vote, longest wins (deterministic tie-break)`
4. `unrelated addresses do NOT consolidate` (defensive)

**519/519 tests pass.** `flutter analyze` clean.

### Consumer impact

No public API changes. Patch release. Bump SHA only.

## 0.6.7 (bugfix)

Address continuation across ML Kit line splits — reported by JC against v0.6.6.

### Symptom

Real DNI back side prints `MZ.B LT.19` on its own visual line, but ML Kit
emits it differently per frame. Sometimes the address line ends at `MZ`
and the lot fragment lands on the next line as `B LT.19` (or just `19`
when LT also lands on the previous line). The previous `_buildAddress`
required the next line to start with a known prefix (`AV.`, `MZ.`, …),
so a "tail-only" continuation like `B LT.19` was dropped:

```
Log: ✅ Dirección: ASENT HI5 DE ABRIL CALLE EL MILAGRO MZ
                                                       ^^ truncated here
```

### Fix

`_buildAddress` now also attaches the next line when the PREVIOUS line
ended with a dangling continuation anchor (`MZ`, `MZA`, `LT`, `LTE`,
`NRO`, `INT`, `DPTO` — with or without trailing dot) and the next line
looks like a short address fragment (≤ 30 chars, alphanumerics + dots,
not a known label).

Defensive guards:
- `≤ 30 char` cap on the next-line fragment prevents stitching unrelated
  long lines.
- Regex denylist for obvious labels (`DIRECCI*`, `DOMICILI*`,
  `DEPARTAMENT*`, `PROVIN*`, `DISTRIT*`, `UBIGEO`, `GRUPO`, `VOTACI*`,
  `DONACI*`, `ORGANO*`, `SANGUINE*`, `FECHA`, `CADUC*`, `NACIM*`,
  `SEXO`, `NACIONAL*`) so we don't pull the next form label into the
  address.
- Only fires when the previous line's LAST token is a dangling anchor —
  a complete `MZ.B` on the previous line is NOT treated as dangling.

### Tests

3 new regression tests in `test/data/strategies/address_field_strategy_test.dart`:

1. `MZ` at end of line1 + `B LT.19` on line2 → joined.
2. `LT` at end of line1 + `19` on line2 → joined.
3. Continuation chain `MZ` → `B` → `LT 19` across three lines.

**515/515 tests pass.** `flutter analyze` clean.

### Consumer impact

No public API changes. Patch release. Bump SHA only.

## 0.6.6 (bugfix)

Two text-OCR fidelity fixes for real Peruvian DNI cards reported by JC
after v0.6.5 verification. Both address the same root cause: the back-side
MRZ (ICAO 9303 TD1) does NOT carry certain data, so we must rely on the
front-side text-OCR to fill the gaps — and the text-OCR pipeline had two
blind spots.

### Bug C — Modern DNI "Apellidos" unified label was ignored

Modern Peruvian DNI cards print a SINGLE `Apellidos` label with both
paternal and maternal surnames joined on one line (e.g. `QUIROZ REMIGIO`).
The text-OCR strategy only recognized the older two-line format
`PRIMER APELLIDO / SEGUNDO APELLIDO`, so it never extracted the maternal
surname from modern cards. The back-side MRZ only carries the paternal
half, so the snapshot ended up with `lastName = QUIROZ` and
`secondLastName = null` — the maternal surname `REMIGIO` was silently
dropped.

**Fix**: `TextOcrFieldStrategy._tryExtractNameByLabel` now also matches
the `Apellidos` label (singular) and splits the joined value:
- 1 token → `lastName` only
- 2 tokens → `lastName` + `secondLastName`
- 3+ tokens → first is paternal, rest joined as maternal (handles
  compound maternal surnames like `DE LA CRUZ`)

Guarded so it does NOT collide with the older `Primer/Segundo Apellido`
labels (those keep matching first).

### Bug D — RENIEC `Ñ→NXX` MRZ encoding was not reversed

The Peruvian MRZ encodes `Ñ` as `NXX` (ICAO 9303 has no `Ñ` codepoint).
Real example: `ERMITAÑO` → `ERMITANXX0`. When the front-side text-OCR
voted the correct `ERMITAÑO` (with real `Ñ`), the snapshot still showed
the corrupted MRZ value because `_recoverTildeFromText` only handled
plain accents (`Á É Í Ó Ú`), not the `NXX` substitution.

**Fix**: `_recoverTildeFromText` now also tries a fallback lookup with
`NXX → N` (and trailing `0 → O`) substitution. When the text-OCR vote
key matches the collapsed MRZ form, the text-OCR display value wins —
recovering both the `Ñ` and any tildes that the MRZ stripped.

No fabrication: when text-OCR did NOT vote a variant, the MRZ value
passes through verbatim (the user fixes it in the confirmation step).

### Tests

8 new regression tests:

`test/data/strategies/text_ocr_field_strategy_test.dart` (Bug C):
1. Splits `Apellidos QUIROZ REMIGIO` into `lastName + secondLastName`.
2. Single-token `Apellidos` leaves `secondLastName` null (no fabrication).
3. 3+ token `Apellidos` uses first as paternal, rest joined as maternal.

`test/data/ocr_consensus_test.dart` (Bug D):
1. `firstName`: MRZ `ERMITANXX0` + text vote `ERMITAÑO` → snapshot `ERMITAÑO`.
2. `lastName`: MRZ `NUNXXEZ` + text vote `NÚÑEZ` → snapshot `NÚÑEZ`.
3. No text-OCR vote → MRZ value passes through unchanged.

`test/data/strategies/address_field_strategy_test.dart` (regression guards):
1. Real JC case: `MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES`.
2. `3ER` / `SECTOR` / `ZONA` tokens preserved in address.

**512/512 tests pass.** `flutter analyze` clean.

### Consumer impact

No public API changes. Patch release. Bump SHA only.

## 0.6.5 (bugfix)

Address parsing quality fix for real Peruvian DNI back-side scans. Reported
after JC's v0.6.4 verification — once the controller flag fix unblocked the
data flow, parsing-side issues became visible.

### Symptom

Real DNI back-side prints:
```
Dirección
ASENT.H15 DE ABRIL CALLE EL MILAGRO
MZ.B LT.19
```

`AddressFieldStrategy._buildAddress` was stopping after the first line
because `MZA 12 LTE 8` (full-form variants) did not match
`_isAddressContinuation`. Long-form Peruvian address codes were dropped.

### Fix

Extended `_isAddressContinuation` prefix list with the long-form variants
of Manzana / Lote (used on rural and formal addresses):

```diff
  const prefixes = [
    'MZ.', 'MZ ',
+   'MZA.', 'MZA ',
    'LT.', 'LT ',
+   'LTE.', 'LTE ',
    'NRO.', 'NRO ',
    'INT.', 'DPTO.',
+   'INT ', 'DPTO ',
  ];
```

Also added the bare-space variants of INT / DPTO that the previous list
missed (only dotted forms were recognized).

### Tests

Four new regression tests in `test/data/strategies/address_field_strategy_test.dart`:

1. `MZ.B and LT.19 are preserved in the final address` — JC's exact case.
2. `ABRIL is preserved (no token mangling)` — guard against shantytown name corruption.
3. `MZ A LT 5 (space-separated, no dots) variant` — alt format.
4. `MZA / LTE (full-word variants) preserved` — the case that triggered the fix.

**504/504 tests pass.** `flutter analyze` clean (0 issues).

### Consumer impact

No public API changes. Patch release. Bump SHA only.

## 0.6.4 (bugfix — CRITICAL)

Closes the "two-sided scan loses OCR" symptom for real. v0.6.1 fixed the
accumulator math, v0.6.3 wired the front-side seed, and this release fixes
the **final** drop point — a stale flag inside `DniCameraController`.

### Root cause

`DniCameraController._isBackSide` was declared `final` and only set in the
constructor. When Flutter REUSES the widget state across the front→back
step transition (which it does — the `KycDocumentScanStep` tree shape is
identical for both steps, so the `DniCameraMask` State is reused), the
controller instance is reused too. `initState` does NOT re-run, so
`_isBackSide` stays `false` even after `onSideChanged(isBackSide: true)`.

`onCaptureDelivered` then passes `_isBackSide ? consensus : null` =
`false ? ... : null` = **null**, dropping the back-side consensus on the
floor right before it would have reached the host callback.

### Observed symptom (JC v0.6.3 logs)

```
🔴 [DniCameraMask] _triggerShutter SHOT:
   isBackSide=true consensus=NOT-NULL firstName=JOSE CARLOS JOAO ✅
🟠 [_onValidCapture] ENTRY:
   isFront=false consensus=NULL ❌
```

The widget logged a valid snapshot, then the host saw null. The drop
happened in `DniCameraController.onCaptureDelivered`.

### Fix

`_isBackSide` is now mutable and synced inside `onSideChanged`:

```dart
void onSideChanged({bool isBackSide = false, ...}) {
  if (_isDisposed) return;
  _isBackSide = isBackSide;   // ← new
  // ...rest of the method unchanged
}
```

### Tests

Two new regression tests in `test/presentation/controllers/dni_camera_controller_test.dart`:

1. Controller constructed front-side → `onSideChanged(isBackSide: true)` →
   `onCaptureDelivered(consensus: nonNull)` MUST deliver the consensus to
   the host. (RED on `main`, GREEN with fix.)
2. Inverse: controller constructed back-side → flipped to front →
   consensus MUST be scrubbed regardless of what the host passes.

500/500 tests pass. `flutter analyze` clean.

### Consumer impact

No public API changes. Patch release. Bump SHA only.

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
