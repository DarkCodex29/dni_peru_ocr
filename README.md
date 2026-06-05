# dni_peru_ocr

Peruvian DNI OCR helpers for Flutter — process the text output of Google ML Kit Latin TextRecognizer against the Documento Nacional de Identidad (Peruvian ID card) and recover clean, structured fields.

## Features

- **Tilde recovery** — Detects and repairs the well-known ML Kit corruption where `Ñ` is read as `NXX` (e.g. `MUNXXOZ` → `MUÑOZ`).
- **Address noise filtering** — Drops QR-derived artifacts, voting-box labels (`CONSTANCIA DE SUFRAGIO`), and corrupted field labels (`DIRECCIS`) from extracted addresses.
- **MRZ parsing** — ICAO 9303 TD1 parsing with checksum validation via `mrz_parser`.
- **Temporal consensus** — Vote across multiple frames to converge on the correct value, with display-value preservation (vote uses ASCII keys, output preserves diacritics).
- **Surname merge** — Tilde-insensitive comparison so OCR `HUAMAN` matches a stored profile `Huamán` for maternal-surname completion.
- **Peruvian address vocabulary** — Pre-loaded with RENIEC SRGDD / INEI address prefixes (`AV`, `JR`, `MZ`, `LT`, `URB`, `AAHH`, `PP.JJ.`, `CP`, `CCNN`, `CASERIO`, `ANEXO`, etc.) and a DNI label denylist.
- **Pluggable logging** — Inject your own observability adapter (Sentry, Crashlytics, Datadog) via the `OcrLogger` interface.

## Installation

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  dni_peru_ocr:
    git:
      url: https://github.com/DarkCodex29/dni_peru_ocr.git
      ref: main
```

Run `flutter pub get`.

## Quick start

```dart
import 'package:dni_peru_ocr/dni_peru_ocr.dart';

final extractor = OcrFieldExtractor(logger: const NoOpOcrLogger());
final fields = extractor.extract(recognizedText);

print(fields.firstName);     // JUAN CARLOS
print(fields.lastName);      // MUÑOZ
print(fields.address);       // AV. SANTA ROSA 1080 MARIATEGUI
```

## API surface

- `OcrFieldExtractor` — extraction entry point.
- `OcrFieldNormalizer` — pure normalization helpers.
- `OcrConsensusAccumulator` — temporal consensus accumulator (formerly `OcrConsensusBuilder`).
- `StringSimilarity` — Levenshtein-based string comparison.
- `OcrLogger` — observability interface (`NoOpOcrLogger` default).

## Logging adapter

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

final extractor = OcrFieldExtractor(logger: const SentryOcrLogger());
```

## Roadmap

### v0.6.0 (current) — Clean Architecture refactor ✅
- ✅ Layered architecture: `domain/`, `data/`, `presentation/`, `infrastructure/` under `lib/src/`.
- ✅ `OcrFieldExtractor` decomposed into `MrzFieldStrategy`, `TextOcrFieldStrategy`, `AddressFieldStrategy`.
- ✅ `DniCameraMask` split into `DniCameraController` (pure Dart) + `DniCaptureOrchestrator` + `DniCameraMask` (widget).
- ✅ Global mutable `OcrExtractedFields.logger` removed — constructor injection via `OcrFieldExtractor(logger:)`.
- ✅ `borderColor` removed from `DocumentValidationResult` — use `ValidationGateColors.colorFor(gate, theme)`.
- ✅ `ValidationGate` enum replaces `String?` for compile-time exhaustive gate matching.
- ✅ `OcrConsensusBuilder` → `OcrConsensusAccumulator` (deprecated typedef alias in place until v0.7.0).
- ✅ GitHub Actions CI: `analyze --fatal-warnings` + `flutter test` on every PR and push to `main`.

### v0.5.0
- ✅ OCR pipeline: field normalization (`Ñ` recovery), MRZ parsing, address noise filtering, temporal consensus.
- ✅ Full DNI scanning widget (`DniCameraMask`) with auto-capture, manual fallback, tilt detection, blink-free flow.
- ✅ Theming via `KycTheme` + `KycThemeProvider`.
- ✅ Pluggable logger (`OcrLogger`).

### Planned — sibling library
- `face_validator_peru`: extract face validation + selfie capture into a separate package, mirroring this one's structure. Today face logic still lives in the consumer app.

## License

MIT — see [LICENSE](LICENSE).
