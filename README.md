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
- `OcrConsensusBuilder` — temporal consensus builder.
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

## License

MIT — see [LICENSE](LICENSE).
