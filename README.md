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
  widget. It ships auto-capture with an IMU stillness gate, a live
  lighting/glare gate, post-shutter blur reject-and-retry, a manual
  fallback after a configurable timeout, tilt detection, side-toggle
  seeding, and a dispose-safe lifecycle. Pure-Dart `DniCameraController`
  is exposed for headless use.

## Installation

```yaml
dependencies:
  dni_peru_ocr: ^0.7.1
```

> Note: as of v0.11.1, `dio` is a direct runtime dependency of this package (required for pub.dev compliance).
> You don't need to add it to your own `pubspec.yaml`.

```bash
flutter pub get
```

### Install from source

```yaml
dependencies:
  dni_peru_ocr:
    git:
      url: https://github.com/DarkCodex29/dni_peru_ocr.git
      ref: v0.7.1
```

## Example

A runnable example app is available under [`example/`](example/). It demonstrates
the complete DNI capture flow — front scan, back scan with `frontSideFields`
seeding, and result display with per-field confidence indicators — on a real
Android or iOS device. See [example/README.md](example/README.md) for setup
instructions and a walkthrough of the recommended integration pattern.

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
final capture. Use `onScanComplete` for the two-sided flow, or
`onSideCaptured` for single-side capture.

```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

DniScanner(
  controller: cameraController,
  fields: DniFields.kyc(),
  onScanComplete: (result) {
    print(result.hunt.firstName);
    print(result.hunt.address);
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
  onScanComplete: (result) { /* ... */ },
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
| `autoCaptureMs` | `1500` | Dwell time the document must stay valid + still before auto-capture fires. |
| `gracePeriodMs` | `600` | Tolerated transient quality/stillness dip mid-countdown before the anchor resets. |
| `manualFallbackMs` | `30000` | Idle time before the manual capture button is surfaced. |
| `minStableFrames` | `3` | Consecutive stable frames required to arm the countdown. |

The IMU thresholds (accelerometer ≈ `0.6 m/s²`, gyroscope ≈ `0.4 rad/s`, EMA
window ≈ 5 samples) and the lighting thresholds (`minLuminance = 40`,
`maxLuminance = 235`, `maxSaturatedFraction = 0.10`) ship as device-tunable
defaults. They are calibrated for typical mid-range phones; adjust them per
device class if your fleet skews very low- or high-end.

## DNI Lookup

Beyond OCR, `dni_peru_ocr` ships a flexible lookup contract so you can fetch
normalized DNI data from any backend. The lookup feature is fully optional —
OCR-only consumers compile and run identically to v0.7.x.

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

## Public API

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
| `DniScanner` | Production capture widget. |
| `DniCameraController` | Pure-Dart capture state machine. |
| `DniCaptureOrchestrator` | Auto-capture countdown logic. |
| `DniCaptureState` (sealed) | Capture state hierarchy. |
| `MotionStillnessGate` | IMU stillness contract (default `SensorsMotionGate`). |
| `LightingGate` | Mean-luminance + glare scorer for live frames. |
| `ImageQualityGate` | Post-shutter blur (Laplacian) sharpness gate. |
| `DocumentValidationResult` | Geometric + OCR validation gate. |
| `ValidationGate` (enum) | Exhaustive failing-gate cases (incl. `lighting`, `glare`). |
| `ValidationGateColors` | Presentation-side gate → color mapping. |
| `KycTheme` / `KycThemeProvider` | Inject visual identity into the capture widget. |
| `UserVerificationData` | Pre-scan user context for OCR-vs-user matching. |

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
├── domain/           — entities + interfaces, pure Dart
│   ├── entities/     (UserVerificationData, ValidationGate)
│   └── interfaces/   (OcrLogger)
├── data/             — extraction strategies + accumulator
│   ├── strategies/   (Mrz / TextOcr / Address)
│   ├── ocr_consensus.dart
│   ├── ocr_field_extractor.dart
│   ├── ocr_field_normalizer.dart
│   ├── address_noise_filter.dart
│   └── string_similarity.dart
├── infrastructure/   — ML Kit / camera lifecycle utilities
└── presentation/     — Flutter widgets + controllers
    ├── controllers/  (DniCameraController)
    ├── orchestrators/(DniCaptureOrchestrator + sealed state)
    ├── widgets/      (DniScanner + sub-widgets)
    └── theme/        (KycTheme + provider)
```

Follows **Clean Architecture** (domain has no Flutter import). Each
layer depends only on its inner neighbours. Strategies follow the
**Strategy pattern**; consensus follows the **Accumulator pattern**.

## Roadmap

### v0.7.0 (current)
- Ubigeo fields (`department`, `province`, `district`).
- Name vote consolidation by strict prefix containment.
- Address `locked` flag requires ≥ 2 corroborating frames.
- `tiltCalculator` becomes a constructor parameter (last global mutable
  static removed from the public surface).
- Deprecated aliases removed: `OcrConsensusBuilder` typedef,
  `OcrFieldExtractor.extractStatic`, `evaluate(theme:)`.
- Property-based shuffle tests + WidgetTester E2E state-lifecycle tests.

### v0.6.x — bug-fix cycle on top of v0.6.0
Nine patch releases addressing real-world DNI OCR cases. See `CHANGELOG.md`.

### v0.6.0
- Clean Architecture refactor (5 PRs).
- Strategy + Accumulator decomposition.
- `DniCameraMask` God Object split into widget + controller + orchestrator.
- GitHub Actions CI on every PR / push to `main`.

### Planned — sibling library
`face_validator_peru`: extract face validation + selfie capture into a
separate package mirroring this one's structure. Face logic currently
lives in the consumer app.

## Testing

```bash
flutter test                # 1069 tests
flutter analyze             # 0 issues on a clean checkout
```

CI runs both on every push and PR (see `.github/workflows/ci.yaml`).

## License

MIT — see [LICENSE](LICENSE).
