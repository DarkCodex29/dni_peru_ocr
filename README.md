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
- **Production-ready capture widget** — `DniCameraMask` ships with
  auto-capture, manual fallback, tilt detection, side-toggle seeding,
  and dispose-safe lifecycle. Pure-Dart `DniCameraController` is exposed
  for headless use.

## Installation

```yaml
dependencies:
  dni_peru_ocr:
    git:
      url: https://github.com/DarkCodex29/dni_peru_ocr.git
      ref: v0.7.0
```

```bash
flutter pub get
```

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

`DniCameraMask` is a Flutter widget that owns the full capture flow.
The host provides a `camera` plugin `CameraController` and listens for
the final capture via the `onValidCapture` callback.

```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

DniCameraMask(
  controller: cameraController,
  isBackSide: false,
  onValidCapture: (file, consensus) {
    // consensus is null on the front side, populated on the back.
    if (consensus != null) {
      print(consensus.firstName.value);
      print(consensus.address.value);
    }
  },
  // Required for two-sided scans: persist front OCR into your state
  // holder and feed it back as the back-side seed.
  onFrontSideOcrUpdated: (fields) => myStateHolder.frontSideOcr = fields,
)

// ...later, when mounting the back-side step:
DniCameraMask(
  controller: cameraController,
  isBackSide: true,
  frontSideFields: myStateHolder.frontSideOcr, // ← seed
  onValidCapture: (file, consensus) { /* ... */ },
)
```

> **Why the state-holder dance?** Flutter destroys widget `State` when
> the host swaps from front to back via a `switch` over an enum step,
> so the front side's accumulated OCR is lost unless the host persists
> it. The `frontSideFields` parameter restores it.

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
| `DniCameraMask` | Production capture widget. |
| `DniCameraController` | Pure-Dart capture state machine. |
| `DniCaptureOrchestrator` | Auto-capture countdown logic. |
| `DniCaptureState` (sealed) | Capture state hierarchy. |
| `DocumentValidationResult` | Geometric + OCR validation gate. |
| `ValidationGate` (enum) | Exhaustive failing-gate cases. |
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
    ├── widgets/      (DniCameraMask + sub-widgets)
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
flutter test                # 529 tests
flutter analyze             # 0 issues on a clean checkout
```

CI runs both on every push and PR (see `.github/workflows/ci.yaml`).

## License

MIT — see [LICENSE](LICENSE).
