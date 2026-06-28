# dni_peru_ocr

Peruvian DNI OCR helpers for Flutter — denoise the Google ML Kit Latin
`TextRecognizer` output against the *Documento Nacional de Identidad* and
recover clean, structured fields with temporal consensus across frames.

[![CI](https://github.com/DarkCodex29/dni_peru_ocr/actions/workflows/ci.yaml/badge.svg)](https://github.com/DarkCodex29/dni_peru_ocr/actions/workflows/ci.yaml)

## Why

A single ML Kit frame on a Peruvian DNI is **noisy**: `Ñ` is encoded as
`NXX` on the MRZ line, address labels (`DIRECCIÓN`) collide with QR
artifacts, civic-box content (`CONSTANCIA DE SUFRAGIO`) drowns the real
address, and document tilt skews block geometry. This package solves
these problems with a **layered, side-by-side strategy pipeline plus a
temporal accumulator** — no manual cleanup required at the consumer.

## Features

- **MRZ parsing** — ICAO 9303 TD1 with checksum validation via
  `mrz_parser`, plus Peruvian-specific `Ñ → NXX` recovery.
- **Strategy decomposition** — three independent extractors
  (`MrzFieldStrategy`, `TextOcrFieldStrategy`, `AddressFieldStrategy`)
  combined by a thin coordinator. Each strategy is stateless and
  individually testable.
- **Temporal consensus** — `OcrConsensusAccumulator` votes across frames
  and emits a deterministic winner even under noisy OCR (address vote
  consolidation tolerates micro-variants; name votes consolidate by
  strict prefix containment).
- **Ubigeo extraction** — populates `department`, `province`, and
  `district` from the back-side administrative line (`ANCASH/SANTA/
  CHIMBOTE`, `/CALLAO/VENTANILLA`, `LIMA/LIMA/VILLA MARIA DEL TRIUNFO`).
- **Pluggable observability** — inject your own `OcrLogger` (Sentry,
  Crashlytics, Datadog, custom) at the extractor constructor.
- **Capture widget** — `DniScanner` is the single production capture
  widget. It ships auto-capture with a centralized capture brain
  (`CaptureCoordinator`, internal), a live 3-2-1 countdown, an IMU
  jolt-reset guard, a live lighting/glare gate, post-shutter blur
  reject-and-retry, a manual fallback after a configurable timeout, tilt
  detection, two-sided front→back handoff, and a dispose-safe lifecycle.
  Capture readiness, countdown, document presence, and the manual
  fallback all flow through one source of truth. The lifecycle-only
  `DniCameraController` is exposed for OCR-consensus and lookup wiring.
- **Document quad detection (hybrid, non-blocking)** — an on-device
  document-quadrilateral detector (`DocumentQuadDetector` port, OpenCV
  adapter via `opencv_dart`, with a pure-Dart fallback). The quad is an
  **enhancement signal**, not a capture gate: auto-capture fires on OCR
  readiness + frame stability, and the quad raises confidence / enables a
  cleaner crop when available. It never blocks a capture, so a present DNI
  is captured even when the quad detector returns no corners on a given
  frame. See [Document quad detection](#document-quad-detection) below.

## Installation

```yaml
dependencies:
  dni_peru_ocr: ^1.0.0
```

> **Breaking platform floor (v1.0.0).** The on-device quad detector depends on
> `opencv_dart`, which relies on Dart Native Assets hooks. That raises the host
> floor to **Flutter `>=3.38.0` / Dart `>=3.10.0`**. Consumers on older
> toolchains must upgrade before adopting v1.0.0.
>
> The native binary (`libdartcv.so`) is trimmed to the modules quad detection
> needs (`core`, `imgproc`, `imgcodecs`); `calib3d` and every other module are
> excluded. Measured per-ABI native cost is ~9.98 MiB on `arm64-v8a`, and an
> App Bundle ships a single ABI per device.

> Note: `dio` is a direct runtime dependency of this package (required for
> pub.dev compliance). You don't need to add it to your own `pubspec.yaml`.

```bash
flutter pub get
```

### Install from source

```yaml
dependencies:
  dni_peru_ocr:
    git:
      url: https://github.com/DarkCodex29/dni_peru_ocr.git
      ref: v1.0.0
```

## Example

A runnable example app is available under [`example/`](example/). It demonstrates
the complete two-sided DNI capture flow — `DniScanner` drives the front→back
handoff internally and emits a single `DniScanResult` — plus result display with
per-field confidence indicators, on a real Android or iOS device. See
[example/README.md](example/README.md) for setup instructions and a walkthrough
of the recommended integration pattern.

## Quick start — headless extraction

```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

// Static entry point — no logger, default strategies.
final fields = OcrFieldExtractor.extract(recognizedText);

print(fields.firstName);      // JUAN CARLOS
print(fields.lastName);       // MUÑOZ
print(fields.secondLastName); // PEREZ
print(fields.address);        // AV. SANTA ROSA 1080 MARIATEGUI
print(fields.department);     // LIMA
print(fields.province);       // LIMA
print(fields.district);       // VILLA MARIA DEL TRIUNFO
```

To route OCR/MRZ mismatch breadcrumbs through your observability stack,
use the instance API:

```dart
const extractor = OcrFieldExtractor(logger: SentryOcrLogger());
final fields = extractor.extractWith(recognizedText);
```

## Quick start — capture widget

`DniScanner` is a Flutter widget that owns the full capture flow. The
host provides a `camera` plugin `CameraController` and listens for the
final capture.

- **Two-sided mode** (`isBackSide == null`, the default): the scanner
  drives the front→back handoff itself and emits a single `DniScanResult`
  through `onScanComplete`.
- **Single-side mode** (`isBackSide: false` or `true`): the scanner scans
  one side and emits a `DniSideScanResult` through `onSideCaptured`.

The constructor `assert` enforces the pairing: two-sided requires
`onScanComplete`; single-side requires `onSideCaptured`.

```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

// Two-sided flow — scanner handles front then back internally.
DniScanner(
  controller: cameraController,
  fields: DniFields.kyc(),
  onScanComplete: (result) {
    print(result.hunt.firstName);
    print(result.hunt.address);
    print(result.frontPhoto.path);
    print(result.backPhoto.path);
  },
)
```

Tuning is optional — every parameter has a sensible default:

```dart
DniScanner(
  controller: cameraController,
  captureMode: DniCaptureMode.auto,   // auto | manual | hybrid
  autoCaptureMs: 1500,                // dwell before auto-capture
  gracePeriodMs: 600,                 // tolerated quality dip mid-countdown
  manualFallbackMs: 30000,            // show manual button after this
  minStableFrames: 3,                 // stable frames required to arm
  scanHints: const DniScanHints(),    // rotating guidance (see below)
  onScanComplete: (result) { /* ... */ },
)
```

### Scan hints

`DniScanHints` configures the rotating, phase-aware guidance shown along
the bottom of the scanner. The copy is intentionally generic — it guides
the physical action (focus, hold still, flip) and never names a specific
DNI field, because the side a field belongs to is not knowable across the
many Peru DNI versions. Defaults are neutral Spanish; pass your own lists
to localize or reword:

```dart
DniScanner(
  controller: cameraController,
  scanHints: const DniScanHints(
    waitingFront: ['Place the document inside the frame', 'Focus the document'],
    extractingFront: ['Hold the document still', 'Hold steady for a moment'],
    waitingBack: ['Flip the document', 'Place it inside the frame'],
    extractingBack: ['Hold the document still'],
    processing: 'Processing…',
    documentAbsent: 'No document detected',
  ),
  onScanComplete: (result) { /* ... */ },
)
```

### Host-callback safety

`DniScanner` treats every callback it hands you — `onScanComplete`,
`onSideCaptured`, and `onDniReady` — as an untrusted boundary. If your
callback throws, the scanner catches the error, keeps the capture flow and
camera alive, and never rethrows into the Flutter framework. A thrown host
callback can no longer tear down the capture session.

Provide the optional `onError` callback to observe these failures; when it is
omitted, the error is logged through `DniLogger` and capture continues.

```dart
DniScanner(
  controller: cameraController,
  onScanComplete: (result) {
    // Your code may throw here without crashing the scanner.
  },
  onError: (error, stack) {
    // Optional. Surface or report the failure however you like.
  },
)
```

## Integration requirements

`DniScanner` reads the device IMU through `sensors_plus`, which raises the
host build floor. The capture pipeline also uses isolates and the `camera`
plugin, but the only new platform constraints come from `sensors_plus`.

### Android

`sensors_plus` requires a modern Android toolchain. Configure your app
module with:

- **Java 17** (`compileOptions` / `kotlinOptions.jvmTarget = "17"`)
- **Android Gradle Plugin ≥ 8.12.1** (recommended minimum)
- **Gradle ≥ 8.13**

The example app in this repository currently pins **AGP 8.11.1**; bump it to
**8.12.1** or newer in your own project to satisfy `sensors_plus`. No runtime
permission is needed for the accelerometer or gyroscope.

### iOS

No `Info.plist` entry is required. `DniScanner` reads **only** the
accelerometer and gyroscope via `sensors_plus`. It never initializes the
barometer (`CMAltimeter`), which is the only sensor that would require
`NSMotionUsageDescription`. Standard `camera` plugin keys
(`NSCameraUsageDescription`) still apply for the preview itself.

### Tuning parameters and defaults

| Parameter | Default | Purpose |
|---|---|---|
| `autoCaptureMs` | `1500` | Dwell time the document must stay aligned and well-lit before auto-capture fires. |
| `gracePeriodMs` | `600` | Tolerated transient quality dip or jolt mid-countdown before the anchor resets. |
| `manualFallbackMs` | `30000` | Idle time before the manual capture button is surfaced. |
| `minStableFrames` | `3` | Consecutive stable frames required to arm the countdown. |

The phone does **not** need to be held perfectly still. Auto-capture arms once
the document is aligned in frame and well-lit; the dwell countdown is the
"hold steady for a moment" step. The IMU is only a jolt guard — it tolerates
normal hand tremor and resets the countdown solely on a deliberate shake. Its
permissive jolt thresholds (accelerometer ≈ `2.5 m/s²`, gyroscope ≈
`1.5 rad/s`, EMA window ≈ 5 samples) and the lighting thresholds
(`minLuminance = 40`, `maxLuminance = 235`, `maxSaturatedFraction = 0.10`) ship
as device-tunable defaults. They are calibrated for typical mid-range phones;
adjust them per device class if your fleet skews very low- or high-end.

## DNI Lookup

Beyond OCR, `dni_peru_ocr` ships a flexible lookup contract so you can fetch
normalized DNI data from any backend. The lookup feature is fully optional —
OCR-only consumers never instantiate any lookup service and pay no behavioral
cost.

### Recommended composition — caching + service

Implement `DniCache` for your storage layer (Hive, Isar, SharedPreferences,
or just in-memory), then compose with a concrete service:

```dart
import 'package:dio/dio.dart';
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

// Minimal in-memory cache — replace with Hive / Isar in production.
class InMemoryDniCache implements DniCache {
  final Map<String, DniData> _store = {};

  @override
  Future<DniData?> get(String dni) async => _store[dni];

  @override
  Future<void> set(String dni, DniData data) async => _store[dni] = data;

  @override
  Future<void> evict(String dni) async => _store.remove(dni);
}

final lookup = CachingDniLookupService(
  delegate: ReniecSunatLookupService(
    httpClient: DioDniHttpClient(Dio()),
    baseUrl: 'https://your-reniec-sunat-backend.example.com',
  ),
  cache: InMemoryDniCache(),
  ttl: const Duration(minutes: 5),
);

final result = await lookup.lookup('43005787');
switch (result) {
  case DniLookupSuccess(:final data):
    print(data.nombreCompleto);
  case DniLookupNotFound():
    print('DNI not found');
  case _:
    print('Lookup failed');
}
```

### Multi-backend fallback

For setups where you want to try a primary service and fall back to a secondary,
use `FallbackDniLookupService`. It stops the chain on `DniLookupInvalidToken`
by default so you do not hammer a service with bad credentials:

```dart
final lookup = FallbackDniLookupService(
  services: [primaryService, secondaryService],
);

final result = await lookup.lookup('43005787');
```

The retry predicate is configurable — pass `retryOn` to override which result
types allow the chain to continue.

## Field Selection

If your app only needs a subset of fields, configure the scanner with a `DniFields` to reduce CPU usage.

```dart
final scanner = DniScanner(
  controller: cameraController,
  fields: DniFields.kyc(),
  onScanComplete: (result) { ... },
);
```

Built-in presets:
- `DniFields.minimal()` — 4 fields (dni, firstName, lastName, secondLastName)
- `DniFields.kyc()` — 7 fields for KYC flows
- `DniFields.full()` — all 19 fields (default behavior when omitted)

Or define a custom set: `DniFields.required({DniField.documentNumber, DniField.firstName, DniField.address})`.

## Document quad detection

v1.0.0 ships an on-device document-quadrilateral detector. It is a **hybrid,
non-blocking enhancement** — be precise about what that means:

| Aspect | Behavior |
|---|---|
| What fires a capture | OCR readiness + frame stability (via `HuntStateMachine`). |
| Role of the quad | An **annotation**: it raises confidence and enables a cleaner perspective crop **when** a clean 4-corner card boundary is found. |
| Can the quad block a capture? | **No.** A present, OCR-confirmed DNI is captured even when the detector returns zero corners on a frame. The quad never vetoes. |
| Native vs fallback | `DocumentQuadDetector` is the domain port. The OpenCV adapter (`opencv_dart`) is selected when the native binary loads; otherwise a pure-Dart `FallbackQuadDetector` is used. A one-time runtime probe picks the adapter and never throws. |

**Honest status.** On real, text-dense DNI frames the native detector frequently
returns no clean quad (text edges are not a card boundary). That is why capture
is driven by OCR + stability, not by the quad. Treat quad corners as a
best-effort enhancement signal, not a reliable edge detector. Improving quad
quality (clean corners on real frames) and post-capture perspective crop are
tracked as future work — see [Roadmap](#roadmap).

The port surface, for consumers who want to supply their own detector:

```dart
abstract interface class DocumentQuadDetector {
  bool get isNativeAvailable;
  QuadDetectionResult detectQuad(QuadFrame frame);
  Uint8List? rectify({required Uint8List imageBytes, required List<QuadCorner> corners});
}
```

`QuadFrame` carries a luminance plane + dimensions; `QuadDetectionResult` carries
`framingValid` and an ordered (TL, TR, BR, BL) corner list that is empty when no
quad is found.

## Public API

### Extraction & consensus

| Type | Purpose |
|---|---|
| `OcrFieldExtractor` | Static + instance extraction coordinator. |
| `OcrExtractedFields` | Mutable field bag (document number, names, address, ubigeo). |
| `OcrConsensusAccumulator` | Per-field vote accumulator across frames. |
| `OcrConsensusResult` | Immutable snapshot of the accumulator. |
| `MrzFieldStrategy` | MRZ-only extractor (checksum-valid). |
| `TextOcrFieldStrategy` | Label-anchored text extractor. |
| `AddressFieldStrategy` | Address + ubigeo extractor with multi-line stitching. |
| `OcrFieldStrategy` | Interface for custom strategies. |
| `OcrFieldNormalizer` | Pure normalization helpers (`Ñ` recovery, document, date). |
| `AddressNoiseFilter` | Peruvian address vocabulary + noise-token filter. |
| `StringSimilarity` | Levenshtein utilities. |
| `OcrLogger` / `NoOpOcrLogger` | Observability hook (default no-op). |

### Field selection & hunt

| Type | Purpose |
|---|---|
| `DniField` (enum) | The 19 extractable DNI fields. |
| `DniFields` | Immutable field selection (`minimal()`, `kyc()`, `full()`, `required({...})`). |
| `FieldHunter` | Per-frame field extraction pipeline honoring a `DniFields` selection. |
| `HuntStateMachine` | OCR-readiness state machine that drives auto-capture eligibility. |
| `HuntResult` / `ExtractedFields` | Per-side hunt output. |

### Capture widget & gates

| Type | Purpose |
|---|---|
| `DniScanner` | The single production capture widget. |
| `DniScanHints` | Configurable, phase-aware rotating guidance (neutral Spanish default). |
| `DniScanResult` / `DniSideScanResult` | Two-sided / single-side capture payloads. |
| `DniCaptureMode` (enum) | `auto` \| `manual` \| `hybrid`. |
| `DniCameraController` | Lifecycle-only controller: OCR-consensus accumulator + lookup pipeline wiring (no capture-state subsystem). |
| `DniCaptureOrchestrator` | Auto-capture countdown logic. |
| `DniCaptureState` (sealed) | Capture state hierarchy (`Scanning`, `CountingDown`, `InFlight`, `Expired`, `Done`). |
| `MotionStillnessGate` | IMU jolt-guard contract (default `SensorsMotionGate`). |
| `LightingGate` | Mean-luminance + glare scorer for live frames. |
| `ImageQualityGate` | Post-shutter blur (Laplacian) sharpness gate. |
| `DocumentValidationResult` | Geometric + OCR validation gate. |
| `ValidationGate` (enum) | Exhaustive failing-gate cases (incl. `lighting`, `glare`). |
| `ValidationGateColors` | Presentation-side gate → color mapping. |
| `KycTheme` / `KycThemeProvider` | Inject visual identity into the capture widget. |
| `UserVerificationData` | Pre-scan user context for OCR-vs-user matching. |

### Document quad detection

| Type | Purpose |
|---|---|
| `DocumentQuadDetector` | Domain port for the hybrid, non-blocking quad detector. |
| `OpenCvQuadDetector` | `opencv_dart`-backed adapter (used when the native binary loads). |
| `FallbackQuadDetector` | Pure-Dart fallback adapter (used when native is unavailable). |
| `QuadFrame` / `QuadCorner` / `QuadDetectionResult` | Quad detection value types. |

### DNI lookup

| Type | Purpose |
|---|---|
| `DniLookupService` | Lookup contract for external DNI data sources. |
| `ApisPeruLookupService` / `ReniecSunatLookupService` | Built-in backend adapters. |
| `CachingDniLookupService` | Cache-aside decorator (TTL, consumer-provided `DniCache`). |
| `FallbackDniLookupService` | Ordered service chain with configurable retry predicate. |
| `DniCache` / `InMemoryDniCache` | Cache contract + in-memory implementation. |
| `DniData` / `DniLookupResult` | Lookup model + sealed result type. |
| `DniHttpClient` / `DioDniHttpClient` | HTTP contract + Dio adapter. |

> The capture brain — `CaptureCoordinator`, `FrameInput`, `FramingSignal`, and
> `CaptureDecision` — is **internal** and intentionally **not exported**. It is
> the single source of truth that owns capture readiness, the 3-2-1 countdown,
> document presence, and the manual fallback behind `DniScanner`.

## Logging adapter example

```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class SentryOcrLogger implements OcrLogger {
  const SentryOcrLogger();

  @override
  void breadcrumb(String category, String message, {Map<String, Object?>? data}) {
    Sentry.addBreadcrumb(
      Breadcrumb(
        category: category,
        message: message,
        data: data,
        level: SentryLevel.info,
      ),
    );
  }
}
```

## Architecture

```
lib/src/
├── domain/           — entities + ports, pure Dart (no Flutter import)
│   ├── entities/     (UserVerificationData, ValidationGate, DocumentSide…)
│   ├── capture/      (DocumentQuadDetector port, MotionStillnessGate, StabilityState)
│   ├── extraction/   (DniField, DniFields, FieldHunter, HuntStateMachine, HuntResult)
│   └── interfaces/   (OcrLogger)
├── data/             — extraction strategies + accumulator
│   ├── strategies/   (Mrz / TextOcr / Address / OcrFieldStrategy)
│   ├── ocr_consensus.dart
│   ├── ocr_field_extractor.dart
│   ├── ocr_field_normalizer.dart
│   ├── address_noise_filter.dart
│   └── string_similarity.dart
├── extraction/       — per-field extractors (dni number, MRZ, dates, ubigeo…)
├── infrastructure/   — ML Kit / camera lifecycle + quad adapters
│   ├── opencv_quad_detector.dart    (opencv_dart adapter; only dartcv4 importer)
│   └── fallback_quad_detector.dart  (pure-Dart fallback)
├── lookup/           — DNI lookup services, cache, decorators, http
└── presentation/     — Flutter widgets + capture brain
    ├── coordinators/ (CaptureCoordinator, CaptureDecision, FrameInput — internal)
    ├── framing/      (FramingSignal — internal)
    ├── controllers/  (DniCameraController — lifecycle-only)
    ├── orchestrators/(DniCaptureOrchestrator + sealed DniCaptureState)
    ├── widgets/      (DniScanner + DniScanHints + sub-widgets)
    └── theme/        (KycTheme + provider)
```

Follows **Clean Architecture** (domain has no Flutter import; the quad detector
is a domain **port** with infrastructure adapters). Each layer depends only on
its inner neighbours. Strategies follow the **Strategy pattern**; consensus
follows the **Accumulator pattern**.

The capture subsystem is **centralized**: a single internal `CaptureCoordinator`
(pure Dart, in `presentation/coordinators/`) owns capture readiness, the 3-2-1
countdown, document presence, and the manual fallback. It consumes a normalized
`FrameInput`, runs the real readiness path (`DocumentSideDetector` →
`HuntStateMachine`), unifies framing through one `FramingSignal`, and emits a
`CaptureDecision`. `DniScanner` is a thin renderer that acts on those decisions;
`DniCameraController` is lifecycle-only. None of these capture-brain types are
exported — only `DniScanner` and its public configuration are.

## Roadmap

### v1.0.0 (current)
- **Platform floor raised** to Flutter `>=3.38.0` / Dart `>=3.10.0` for the
  `opencv_dart` Native Assets dependency (the MAJOR bump).
- **Document quad detection** (`DocumentQuadDetector` port + OpenCV adapter +
  pure-Dart fallback) shipped as a hybrid, **non-blocking** enhancement.
- **Capture subsystem redesign**: a single internal `CaptureCoordinator` owns
  capture readiness, the 3-2-1 countdown, document presence, and the manual
  fallback. Cured the front auto-capture reliability, the false "no document"
  banner on a held front DNI, and the stay-still-after-countdown symptoms.
- **`DniScanner` is the single, canonical capture widget**; the legacy
  `DniCameraMask` was removed.
- Configurable `DniScanHints` (neutral Spanish default).

### Future work
- **Quad quality** — real DNI frames frequently return `corners = 0` (text edges
  are not a card boundary). Improving clean-corner detection on real frames is
  open work; until then the quad stays a non-blocking enhancement and capture is
  driven by OCR + stability.
- **Post-capture perspective crop** — rectify the captured still using the quad
  corners when a clean quad is available.

### Earlier history
See `CHANGELOG.md` for the full pre-1.0 history (Clean Architecture refactor,
Strategy + Accumulator decomposition, the ubigeo feature, the DNI lookup
contract, and the v0.6.x real-world bug-fix cycle).

### Planned — sibling library
`face_validator_peru`: extract face validation + selfie capture into a
separate package mirroring this one's structure. Face logic currently
lives in the consumer app.

## Testing

```bash
flutter test                # ~1260 test/testWidgets calls, 1301 cases pass
flutter analyze             # 0 issues in lib/ and example/
```

The suite includes a **device-faithful capture harness** that drives real
`CameraImage`-equivalent frame sequences through the real
`DocumentSideDetector` → `HuntStateMachine` → `CaptureCoordinator` path, plus a
**golden capture oracle** that pins the sacred "both sides auto-capture"
behavior end-to-end. CI runs `flutter test` and `flutter analyze` on every push
and PR (see `.github/workflows/ci.yaml`).

## License

MIT — see [LICENSE](LICENSE).
