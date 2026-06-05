import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';

import 'ocr_field_normalizer.dart';
import 'strategies/address_field_strategy.dart';
import 'strategies/mrz_field_strategy.dart';
import 'strategies/ocr_field_strategy.dart';
import 'strategies/text_ocr_field_strategy.dart';
import '../domain/interfaces/ocr_logger.dart';

/// Container for fields extracted from a single OCR frame.
///
/// Mutable on purpose: the extractor merges values across frames in-place.
/// A snapshot of [_fromMrz] tracks whether the values originated from
/// MRZ checksum-valid parsing (highest confidence) or from text-OCR
/// fallback heuristics. MRZ values always win on merge.
class OcrExtractedFields {
  String? documentNumber;
  String? firstName;
  String? lastName;
  String? secondLastName;
  String? dateOfBirth;
  String? sex;
  String? expirationDate;
  String? nationality;
  String? address;

  /// Logger used by [_reportMismatch] to record OCR/MRZ mismatches.
  /// Defaults to a no-op; assign once at app startup to wire your
  /// observability platform.
  static OcrLogger logger = const NoOpOcrLogger();

  void merge(OcrExtractedFields other) {
    // MRZ-sourced incoming always wins over text-OCR current.
    // When merging text into an MRZ accumulator, MRZ is preserved.
    final incomingIsMrz = other._fromMrz;
    final currentIsMrz = _fromMrz;

    documentNumber = _bestWithMrz(
      current: documentNumber,
      incoming: other.documentNumber,
      fieldName: 'documentNumber',
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    firstName = _best(
      firstName,
      other.firstName,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    lastName = _best(
      lastName,
      other.lastName,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    secondLastName = _best(
      secondLastName,
      other.secondLastName,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    dateOfBirth = _best(
      dateOfBirth,
      other.dateOfBirth,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    sex = _best(
      sex,
      other.sex,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    expirationDate = _best(
      expirationDate,
      other.expirationDate,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );
    nationality = _best(
      nationality,
      other.nationality,
      incomingIsMrz: incomingIsMrz,
      currentIsMrz: currentIsMrz,
    );

    // address is never MRZ-sourced; prefer the longer (more complete) value.
    address = _best(
      address,
      other.address,
      incomingIsMrz: false,
      currentIsMrz: false,
    );

    // Promote MRZ flag if incoming was MRZ-sourced.
    if (incomingIsMrz) _fromMrz = true;
  }

  /// Merges [documentNumber] with a logger breadcrumb on mismatch.
  String? _bestWithMrz({
    required String? current,
    required String? incoming,
    required String fieldName,
    required bool incomingIsMrz,
    required bool currentIsMrz,
  }) {
    if (incoming == null || incoming.isEmpty) return current;
    if (current == null || current.isEmpty) return incoming;

    // MRZ incoming wins unconditionally over text-OCR current.
    if (incomingIsMrz && !currentIsMrz) {
      if (incoming != current) {
        _reportMismatch(fieldName, ocrValue: current, mrzValue: incoming);
      }
      return incoming;
    }

    // Text-OCR incoming does NOT overwrite an MRZ-sourced current.
    if (!incomingIsMrz && currentIsMrz) return current;

    // Both same source — prefer longer (original heuristic).
    return incoming.length >= current.length ? incoming : current;
  }

  String? _best(
    String? current,
    String? incoming, {
    required bool incomingIsMrz,
    required bool currentIsMrz,
  }) {
    if (incoming == null || incoming.isEmpty) return current;
    if (current == null || current.isEmpty) return incoming;

    if (incomingIsMrz && !currentIsMrz) return incoming;
    if (!incomingIsMrz && currentIsMrz) return current;

    // Both same source — prefer longer (original heuristic).
    return incoming.length >= current.length ? incoming : current;
  }

  static void _reportMismatch(
    String field, {
    required String ocrValue,
    required String mrzValue,
  }) {
    logger.breadcrumb(
      'kyc-ocr-mrz-mismatch',
      'KYC OCR/MRZ mismatch on $field: ocr="$ocrValue" mrz="$mrzValue"',
      data: {
        'field': field,
        'ocr': ocrValue,
        'mrz': mrzValue,
      },
    );
  }

  int get foundCount => fields.values.where((v) => v != null).length;
  int get totalCount => fields.length;
  bool get hasMrzData => _fromMrz;
  bool _fromMrz = false;

  /// Marks this instance as MRZ-sourced.
  ///
  /// Called by [MrzFieldStrategy] after a successful MRZ parse.
  /// Callers outside this package should use [hasMrzData] for reads.
  // ignore: avoid_setters_without_getters
  set markAsMrzSourced(bool value) => _fromMrz = value;

  /// Test-only helper — marks this instance as MRZ-sourced without going
  /// through the full MRZ parsing path. Callers should use [hasMrzData]
  /// for reads; a dedicated getter is intentionally omitted here.
  @visibleForTesting
  // ignore: avoid_setters_without_getters
  set fromMrzForTest(bool value) => _fromMrz = value;

  Map<String, String?> get fields => {
    'N° Documento': documentNumber,
    'Apellido paterno': lastName,
    'Apellido materno': secondLastName,
    'Nombres': firstName,
    'Nacimiento': dateOfBirth,
    'Sexo': sex,
    'Caducidad': expirationDate,
    'Nacionalidad': nationality,
    'Dirección': address,
  };

  @override
  String toString() {
    final buf = StringBuffer();
    final src = _fromMrz ? ' [MRZ]' : '';
    for (final entry in fields.entries) {
      final status = entry.value != null ? '✅' : '⬜';
      buf.writeln('$status ${entry.key}: ${entry.value ?? '—'}$src');
    }
    return buf.toString();
  }
}

/// Thin coordinator that turns [RecognizedText] into [OcrExtractedFields]
/// by delegating to three focused strategies.
///
/// Strategy order:
/// 1. [MrzFieldStrategy] — highest confidence, all fields except address.
/// 2. [TextOcrFieldStrategy] — label-anchored heuristics (skipped when MRZ
///    succeeded, except for `secondLastName` back-fill on DNI azul).
/// 3. [AddressFieldStrategy] — always runs (address is never in MRZ).
///
/// All strategies are stateless. The default instance uses the standard
/// three strategies; pass a custom [List<OcrFieldStrategy>] to the
/// constructor for testing or alternative pipelines.
class OcrFieldExtractor {
  /// Creates a coordinator with the default three strategies.
  const OcrFieldExtractor([List<OcrFieldStrategy>? strategies])
      : _strategies = strategies;

  final List<OcrFieldStrategy>? _strategies;

  /// Runs the extraction pipeline using this instance's strategy list.
  OcrExtractedFields extractWith(RecognizedText recognized) {
    final mrz = _mrzStrategy;
    final text = _textStrategy;
    final address = _addressStrategy;
    return _runPipeline(recognized, mrz, text, address);
  }

  OcrFieldStrategy get _mrzStrategy =>
      _strategies?.whereType<MrzFieldStrategy>().firstOrNull ??
      const MrzFieldStrategy();

  OcrFieldStrategy get _textStrategy =>
      _strategies?.whereType<TextOcrFieldStrategy>().firstOrNull ??
      const TextOcrFieldStrategy();

  OcrFieldStrategy get _addressStrategy =>
      _strategies?.whereType<AddressFieldStrategy>().firstOrNull ??
      const AddressFieldStrategy();

  /// Runs the extraction pipeline on [recognized] and returns the merged
  /// [OcrExtractedFields]. Returns an empty instance when no blocks are
  /// present.
  ///
  /// Uses the default three strategies (MRZ → Text → Address).
  static OcrExtractedFields extract(RecognizedText recognized) {
    return _runPipeline(
      recognized,
      const MrzFieldStrategy(),
      const TextOcrFieldStrategy(),
      const AddressFieldStrategy(),
    );
  }

  static OcrExtractedFields _runPipeline(
    RecognizedText recognized,
    OcrFieldStrategy mrzStrategy,
    OcrFieldStrategy textStrategy,
    OcrFieldStrategy addressStrategy,
  ) {
    final empty = OcrExtractedFields();
    if (recognized.blocks.isEmpty) return empty;

    // Step 1: Try MRZ — highest confidence source.
    final mrzResult = mrzStrategy.extract(recognized);

    if (mrzResult != null) {
      // Step 2 (address): always runs — address is never in MRZ.
      final addressResult = addressStrategy.extract(recognized);
      if (addressResult?.address != null) {
        mrzResult.address = addressResult!.address;
      }

      // Step 3 (secondLastName back-fill): DNI azul has the "Segundo Apellido"
      // label on the same physical side as the MRZ. MRZ only carries one
      // surname, so extract the second surname from text if MRZ missed it.
      if (mrzResult.secondLastName == null) {
        final textResult = textStrategy.extract(recognized);
        if (textResult?.secondLastName != null) {
          mrzResult.secondLastName = textResult!.secondLastName;
        }
      }

      return mrzResult;
    }

    // Step 1 failed: run text-OCR extraction.
    final textResult = textStrategy.extract(recognized) ?? OcrExtractedFields();

    // Step 2 (address): always runs.
    final addressResult = addressStrategy.extract(recognized);
    if (addressResult?.address != null) {
      textResult.address = addressResult!.address;
    }

    return textResult;
  }

  /// Attempts to locate and parse MRZ lines from [recognized].
  /// Returns `null` when no valid MRZ is found.
  static OcrExtractedFields? _tryParseMrz(RecognizedText recognized) {
    final candidateLines = <String>[];

    for (final block in recognized.blocks) {
      final blockText = block.text.replaceAll(' ', '');
      // An MRZ block has many `<` fillers and is long.
      if ('<'.allMatches(blockText).length >= 3 && blockText.length >= 20) {
        // Split by lines and clean OCR-noise substitutions.
        for (final rawLine in block.text.split('\n')) {
          final clean = rawLine
              .replaceAll(' ', '')
              .replaceAll('K', '<')
              .replaceAll('k', '<')
              .replaceAll('«', '<')
              .trim();
          if (clean.length >= 20 && _looksLikeMrz(clean)) {
            // Pad to 30 or 44 chars when truncated by partial OCR.
            final padded = clean.padRight(
              clean.length < 35 ? 30 : 44,
              '<',
            );
            candidateLines.add(padded);
            if (kDebugMode) debugPrint('  MRZ candidata: "$padded"');
          }
        }
      }
    }

    if (candidateLines.length < 2) return null;

    // Peruvian DNI uses TD1 (3 lines × 30 chars) or TD3 (2 lines × 44 chars).
    for (int i = 0; i < candidateLines.length - 1; i++) {
      // Try TD3 (2 lines).
      final pair = [candidateLines[i], candidateLines[i + 1]];
      final td3Result = _tryParseLines(pair);
      if (td3Result != null) return td3Result;

      // Try TD1 (3 lines).
      if (i + 2 < candidateLines.length) {
        final triple = [
          candidateLines[i],
          candidateLines[i + 1],
          candidateLines[i + 2],
        ];
        final td1Result = _tryParseLines(triple);
        if (td1Result != null) return td1Result;
      }
    }

    return null;
  }

  static bool _looksLikeMrz(String line) {
    final mrzChars = RegExp('[A-Z0-9<]');
    final mrzCount = mrzChars.allMatches(line).length;
    return mrzCount > line.length * 0.8;
  }

  static OcrExtractedFields? _tryParseLines(List<String> lines) {
    try {
      final result = MRZParser.tryParse(lines);
      if (result == null) return null;

      final fields = OcrExtractedFields()
        .._fromMrz = true
        ..documentNumber = result.documentNumber
        ..nationality = result.nationalityCountryCode;

      // Split surnames (MRZ packs paternal + maternal into `surnames`).
      final surnames = result.surnames.split(' ');
      if (surnames.isNotEmpty) fields.lastName = surnames.first;
      if (surnames.length > 1) {
        fields.secondLastName = surnames.sublist(1).join(' ');
      }

      fields.firstName = result.givenNames;

      // Guard: when OCR reads `<<` as `<`, the MRZ parser folds the given
      // names into surnames. The resulting `secondLastName == firstName`
      // (same content, possibly with 0/O substitution) — null out the
      // false split so the text-OCR vote from the front side can win in
      // consensus.
      if (fields.secondLastName != null && fields.firstName != null) {
        final sln = fields.secondLastName!.toUpperCase().replaceAll('0', 'O');
        final fn = fields.firstName!.toUpperCase().replaceAll('0', 'O');
        if (sln == fn) fields.secondLastName = null;
      }

      final dob = result.birthDate;
      fields.dateOfBirth =
          '${dob.day.toString().padLeft(2, '0')}/'
          '${dob.month.toString().padLeft(2, '0')}/'
          '${dob.year}';

      final exp = result.expiryDate;
      fields
        ..expirationDate =
            '${exp.day.toString().padLeft(2, '0')}/'
            '${exp.month.toString().padLeft(2, '0')}/'
            '${exp.year}'
        ..sex = result.sex == Sex.male ? 'M' : 'F';

      return fields;
    } on Exception catch (_) {
      return null;
    }
  }

  // ── Fallback: text-block extraction ────────────────────────────────────

  static void _extractFromTextBlocks(
    RecognizedText recognized,
    OcrExtractedFields result,
  ) {
    final lines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !_looksLikeMrzLine(trimmed)) {
          lines.add(trimmed);
        }
      }
    }

    for (int i = 0; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();

      if (result.documentNumber == null) {
        final dniMatch = RegExp('DNI[/\\s]*(\\d{8})').firstMatch(upper);
        if (dniMatch != null) result.documentNumber = dniMatch.group(1);
      }

      _tryExtractNameByLabel(lines, i, result);
      _tryExtractDates(lines, i, result);
      _tryExtractAddress(lines, i, result);

      if (result.sex == null &&
          (upper.contains('SEXO') || upper.contains('ESTADO C'))) {
        final sexMatch = RegExp('\\b([MF])\\b').firstMatch(upper);
        if (sexMatch != null) result.sex = sexMatch.group(1);
      }
    }

    // Pass 2: ordinal matching for two-column DNI layouts (e.g. DNI azul)
    // where all labels appear in one OCR block and all values in another.
    // Adjacent lookup (pass 1) fails because label[i] and value[i+3] are
    // not neighbors in the flat lines list. Instead we collect labels and
    // person-name values in document order and match by position.
    if (result.lastName == null ||
        result.secondLastName == null ||
        result.firstName == null) {
      _extractNamesByOrdinal(lines, result);
    }
  }

  /// Collects name labels and person-name values in document order, then
  /// assigns them by ordinal: 1st label → 1st value, 2nd → 2nd, etc.
  static void _extractNamesByOrdinal(
    List<String> lines,
    OcrExtractedFields result,
  ) {
    // Field name in the order the label was seen.
    final labelOrder = <String>[];
    // Values that pass [_isPersonName], in the order they appear.
    final namePool = <String>[];

    for (final line in lines) {
      final upper = line.toUpperCase().trim();
      if (upper.contains('PRIMER APEL') || upper.contains('PRMER APEL')) {
        if (!labelOrder.contains('lastName')) labelOrder.add('lastName');
      } else if (upper.contains('SEGUNDO APEL') ||
          upper.contains('SGUNDO APEL')) {
        if (!labelOrder.contains('secondLastName')) {
          labelOrder.add('secondLastName');
        }
      } else if (upper.contains('PRENOMBRES') ||
          upper.contains('PRE NOMBRE') ||
          upper.contains('PRE NOM')) {
        if (!labelOrder.contains('firstName')) labelOrder.add('firstName');
      } else if (_isPersonName(line.trim())) {
        namePool.add(line.trim().toUpperCase());
      }
    }

    for (int i = 0; i < labelOrder.length && i < namePool.length; i++) {
      final field = labelOrder[i];
      final name = OcrFieldNormalizer.normalizeForDisplay(namePool[i]);
      if (field == 'lastName') result.lastName ??= name;
      if (field == 'secondLastName') result.secondLastName ??= name;
      if (field == 'firstName') result.firstName ??= name;
    }
  }

  /// Returns true when a single OCR line looks like a MRZ line:
  /// at least 20 chars (after stripping spaces) and 3+ `<` fillers.
  /// Used for line-level filtering so non-MRZ lines in the same block
  /// (e.g. `ALEMAN` just above the MRZ strip) are preserved.
  static bool _looksLikeMrzLine(String line) {
    final clean = line.replaceAll(' ', '');
    return clean.length >= 20 && '<'.allMatches(clean).length >= 3;
  }

  static void _tryExtractNameByLabel(
    List<String> lines,
    int i,
    OcrExtractedFields result,
  ) {
    final upper = lines[i].toUpperCase();

    if (upper.contains('PRIMER APEL') || upper.contains('PRMER APEL')) {
      final value = _findNameNear(lines, i);
      if (value != null) result.lastName ??= value;
    }

    if (upper.contains('SEGUNDO APEL') || upper.contains('SGUNDO APEL')) {
      final value = _findNameNear(lines, i);
      if (value != null) result.secondLastName ??= value;
    }

    if (upper.contains('PRENOMBRES') ||
        upper.contains('PRE NOMBRE') ||
        upper.contains('PRE NOM')) {
      final value = _findNameNear(lines, i);
      if (value != null) result.firstName ??= value;
    }
  }

  static String? _findNameNear(List<String> lines, int labelIdx) {
    if (labelIdx + 1 < lines.length) {
      final next = lines[labelIdx + 1].trim();
      if (_isPersonName(next)) {
        return OcrFieldNormalizer.normalizeForDisplay(next);
      }
    }
    if (labelIdx > 0) {
      final prev = lines[labelIdx - 1].trim();
      if (_isPersonName(prev)) {
        return OcrFieldNormalizer.normalizeForDisplay(prev);
      }
    }
    return null;
  }

  static void _tryExtractDates(
    List<String> lines,
    int i,
    OcrExtractedFields result,
  ) {
    final line = lines[i];
    final upper = line.toUpperCase();
    final dateRegex = RegExp('(\\d{2})\\s+(\\d{2})\\s+(\\d{4})');
    final matches = dateRegex.allMatches(line).toList();
    if (matches.isEmpty) return;

    final context = i > 0 ? '${lines[i - 1].toUpperCase()} $upper' : upper;

    for (final match in matches) {
      final d = int.tryParse(match.group(1)!) ?? 0;
      final m = int.tryParse(match.group(2)!) ?? 0;
      final y = int.tryParse(match.group(3)!) ?? 0;
      if (y < 1950 || y > 2035 || m < 1 || m > 12 || d < 1 || d > 31) continue;

      final date = '${match.group(1)}/${match.group(2)}/${match.group(3)}';

      if (context.contains('NACIMIENTO')) {
        result.dateOfBirth = date;
      } else if (context.contains('CADUC')) {
        result.expirationDate = date;
      } else if (y < 2010 && result.dateOfBirth == null) {
        result.dateOfBirth = date;
      } else if (y > 2026 && result.expirationDate == null) {
        result.expirationDate = date;
      }
    }
  }

  /// Builds a flat lines list from non-MRZ blocks and searches for the
  /// `Segundo Apellido` label. Called after a successful MRZ parse on
  /// documents where the label is on the same physical side as the MRZ
  /// (Peruvian DNI azul front).
  static void _extractSecondLastNameOnly(
    RecognizedText recognized,
    OcrExtractedFields result,
  ) {
    final lines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !_looksLikeMrzLine(trimmed)) {
          lines.add(trimmed);
        }
      }
    }
    for (int i = 0; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();
      if (upper.contains('SEGUNDO APEL') || upper.contains('SGUNDO APEL')) {
        final value = _findNameNear(lines, i);
        if (value != null) {
          result.secondLastName = value;
          return;
        }
      }
    }
  }

  /// Builds a flat lines list from non-MRZ blocks and runs address-only
  /// extraction into [result]. Called after a successful MRZ parse so
  /// the address field (absent from MRZ) can still be populated.
  static void _extractAddressOnly(
    RecognizedText recognized,
    OcrExtractedFields result,
  ) {
    final lines = <String>[];
    for (final block in recognized.blocks) {
      for (final line in block.text.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty && !_looksLikeMrzLine(trimmed)) {
          lines.add(trimmed);
        }
      }
    }
    for (int i = 0; i < lines.length; i++) {
      _tryExtractAddress(lines, i, result);
      if (result.address != null) return;
    }
  }

  /// Three strategies, tried in order:
  ///   1. `DOMICILIO` label — value inline or on next lines.
  ///   2. Peruvian address prefix (`ASEN`, `AV.`, `JR.`, `CALLE`, …) — direct content.
  ///   3. Ubigeo anchor (`DEPT/PROV/DIST`) — address is 1-3 lines above.
  ///
  /// All three strategies funnel the recovered address through
  /// [cleanAddressLine] (per-line QR/barcode noise filter) and
  /// [stripAddressLabelTail] (defensive label strip at head and tail)
  /// before assigning to `result.address`.
  static void _tryExtractAddress(
    List<String> lines,
    int i,
    OcrExtractedFields result,
  ) {
    if (result.address != null) return;
    final upper = lines[i].toUpperCase().trim();

    // Strategy 1: `DOMICILIO` label.
    if (upper.contains('DOMICILIO') ||
        upper.startsWith('DOM ') ||
        upper == 'DOM.') {
      final inlineValue = upper
          .replaceAll(RegExp(r'DOMICILIO\.?:?\s*'), '')
          .trim();
      if (inlineValue.length >= 5 && _isValidAddress(inlineValue)) {
        _assignFilteredAddress(result, inlineValue);
        return;
      }
      for (int offset = 1; offset <= 2; offset++) {
        final idx = i + offset;
        if (idx >= lines.length) break;
        final candidate = lines[idx].trim().toUpperCase();
        if (_isValidAddress(candidate)) {
          _assignFilteredAddress(result, _buildAddress(lines, idx));
          return;
        }
      }
      return;
    }

    // Strategy 2: Peruvian address prefix on the current line.
    if (_hasAddressPrefix(upper)) {
      _assignFilteredAddress(result, _buildAddress(lines, i));
      return;
    }

    // Strategy 3: Ubigeo line as anchor — collect all address lines above
    // it. The address may span multiple lines (e.g. `ASEN 913 DE CALLE EL
    // MILAGRO` on one line and `MZ.B LT.13` on the next), so the scan goes
    // upward up to 4 lines and gathers every valid segment, then joins
    // them in document order.
    //
    // Each candidate line is funneled through [cleanAddressLine] so that
    // QR/barcode artifacts read as Latin text are dropped at the line
    // level, and corrupted `Dirección` labels that survive are scrubbed
    // by [stripAddressLabelTail].
    if (_isUbigeoLine(upper)) {
      final segments = <String>[];
      for (int offset = 4; offset >= 1; offset--) {
        final idx = i - offset;
        if (idx < 0) continue;
        final candidate = lines[idx].trim().toUpperCase();
        final cleaned = cleanAddressLine(candidate);
        if (cleaned == null) continue;
        if (_hasAddressPrefix(cleaned) ||
            _isAddressContinuation(cleaned) ||
            _isValidAddress(cleaned)) {
          segments.add(cleaned);
        }
      }
      if (segments.isNotEmpty) {
        final joined = segments.join(' ');
        final stripped = stripAddressLabelTail(joined);
        result.address = stripped.isEmpty ? null : stripped;
        return;
      }
    }
  }

  /// Funnels a raw recovered address through [cleanAddressLine] and
  /// [stripAddressLabelTail] before assigning. If the cleaner rejects
  /// the whole string (noise ratio > 40%) or the strip leaves nothing,
  /// the assignment is skipped so `result.address` stays null.
  static void _assignFilteredAddress(
    OcrExtractedFields result,
    String rawAddress,
  ) {
    final cleaned = cleanAddressLine(rawAddress);
    if (cleaned == null) return;
    final stripped = stripAddressLabelTail(cleaned);
    if (stripped.isEmpty) return;
    result.address = stripped;
  }

  /// Builds the address string starting at [startIdx], collecting up to 3
  /// additional lines while they look like address continuations or
  /// segments.
  static String _buildAddress(List<String> lines, int startIdx) {
    final parts = <String>[lines[startIdx].trim().toUpperCase()];
    for (int j = startIdx + 1; j < lines.length && j <= startIdx + 3; j++) {
      final next = lines[j].trim().toUpperCase();
      if (_isAddressContinuation(next) || _hasAddressPrefix(next)) {
        parts.add(next);
      } else {
        break;
      }
    }
    return parts.join(' ');
  }

  static bool _hasAddressPrefix(String upper) {
    const prefixes = [
      'AV. ',
      'AV ',
      'JR. ',
      'JR ',
      'CALLE ',
      'PSJ. ',
      'PSJ ',
      'URB. ',
      'URB ',
      'PP.JJ. ',
      'A.H. ',
    ];
    if (prefixes.any(upper.startsWith)) return true;
    // Match all ASEN variants: `ASEN 913`, `ASENT H15`, `ASENTH. 15`, `ASEN913`.
    if (upper.startsWith('ASEN') && upper.length > 4) return true;
    return false;
  }

  static bool _isAddressContinuation(String upper) {
    const prefixes = [
      'MZ.',
      'MZ ',
      'LT.',
      'LT ',
      'NRO.',
      'NRO ',
      'INT.',
      'DPTO.',
    ];
    return prefixes.any(upper.startsWith);
  }

  /// Matches Peruvian ubigeo lines. Accepts the canonical 3-segment
  /// `DEPT/PROV/DIST` (e.g. `LIMA/LIMA/MIRAFLORES`) AND the 2-segment
  /// shorthand that ML Kit sometimes produces on DNI electrónico backs
  /// (e.g. `/CALLAO/VENTANILLA`, with optional leading slash).
  static bool _isUbigeoLine(String upper) => RegExp(
    r'^/?[A-ZÁÉÍÓÚÑ\s]+(?:/[A-ZÁÉÍÓÚÑ\s]+){1,3}$',
  ).hasMatch(upper);

  // ── Address noise filter ───────────────────────────────────────────────
  //
  // Hardens Strategy 3 (and 1/2) of [_tryExtractAddress] against QR/barcode
  // text artifacts ML Kit reads as Latin (`WHAPP AGE 0-- AT 220S MG`) and
  // against corrupted `Dirección` labels (`DIRECCIS`, `DIRECCI`, …).
  //
  // Design:
  //   • Per-line noise ratio: any line with > 40% non-address tokens is
  //     dropped wholesale (no partial mid-line stripping).
  //   • Address-token classifier: whitelist of Peruvian address prefixes,
  //     Spanish connectors, alphanumeric codes (`MZ.C`, `LT.20`, `3ER`,
  //     `220S`, roman I-X), and a phonotactic-shaped "likely Spanish word"
  //     check.
  //   • Label-tail strip: removes corrupted `DIRECC*` / `DOMICIL*` tokens
  //     from BOTH head and tail of the joined address.

  /// Peruvian address prefix whitelist. Tokens are kept regardless of
  /// length. All entries are stored with dots stripped (matching the
  /// dot-stripping behaviour of [_normalizeAddressToken]) so dotted
  /// compound abbreviations like `PP.JJ.`, `A.H.`, `AA.HH.` are matched.
  static const _kAddressPrefixes = <String>{
    'AV',
    'AVENIDA',
    'JR',
    'JIRON',
    'CALLE',
    'PSJE',
    'PSJ',
    'PJ',
    'PASAJE',
    'MZ',
    'LT',
    'URB',
    'AAHH',
    'PP',
    'JJ',
    'PPJJ',
    'ASEN',
    'ASENT',
    'AH',
    'SECTOR',
    'ZONA',
    'ETAPA',
    'NRO',
    'INT',
    'DPTO',
    'KM',
    'PROL',
    'PROLG',
    'CARRETERA',
    'PISO',
    // RENIEC SRGDD + INEI official Peru address vocabulary.
    // Rural, residential complex, and indigenous community prefixes that
    // real citizens carry on their DNI.
    'CP', 'CPM', // Centro Poblado / Centro Poblado Menor
    'CC', 'CCNN', // Comunidad Campesina / Comunidad Nativa
    'CAS', 'CASERIO',
    'ANEXO', 'ANX',
    'RES', 'RESIDENCIAL',
    'COND', 'CONDOMINIO',
    'EDIF', 'EDIFICIO',
    'BLOCK', 'BLK',
    'TORRE', 'TR',
    'PSO',
    'BARRIO', 'BARR',
    'COOP', 'COOPERATIVA',
    'VILLA',
    'FUNDO', 'PARC', 'PARCELA',
    'PARQUE', 'PQ',
  };

  /// Spanish short-word connectors common in addresses.
  static const _kAddressConnectors = <String>{
    'DE',
    'DEL',
    'LA',
    'EL',
    'LAS',
    'LOS',
    'Y',
  };

  /// Tokens that appear printed on the Peruvian DNI back as LABELS or
  /// voting-box content, not as part of the address. These are valid
  /// Spanish words so they pass [_isLikelySpanishWord], but they must
  /// never enter the address output.
  ///
  /// All tokens are uppercased + diacritic-free for matching via
  /// [_denylistKey].
  static const _kAddressNoiseDenylist = <String>{
    // Voting / civic boxes
    'CONSTANCIA',
    'SUFRAGIO',
    'VOTACION', // also catches VOTACIÓN after diacritic strip
    'GRUPO',
    'MESA',
    'ELECCIONES',
    'ELECTORAL',
    // Card labels / sections
    'DOMICILIO',
    'DIRECCION', // also catches DIRECCIÓN
    'DEPARTAMENTO',
    'PROVINCIA',
    'DISTRITO',
    'DONACION',
    'ORGANOS',
    'SANGUINEO',
    'UBIGEO',
    'NACIMIENTO',
    'FECHA',
    'VENCIMIENTO',
    'NACIONALIDAD',
    'JEFA',
    'NACIONAL',
    // RENIEC institutional / republic
    'RENIEC',
    'REPUBLICA',
    'REGISTRO',
    'IDENTIFICACION',
    'ESTADO',
    'CIVIL',
    'SEXO',
    // Common label corruptions from ML Kit on the tilde'd "ó":
    'DIRECCIS',
    'DIRECCI',
    'DIREC',
    'DOMICILI',
    // DNI front-side labels (defense in depth).
    // PRIMER / SEGUNDO / NOMBRE(S) intentionally excluded — they appear
    // in real street names ("PRIMERA DE OCTUBRE") or are too generic.
    'DOCUMENTO',
    'IDENTIDAD',
    'CUI',
    'APELLIDO',
    'APELLIDOS',
    'PRENOMBRES',
    'EMISION',
    'CADUCIDAD',
    'TARJETA',
    'NUMERO',
    'SOLTERO',
    'SOLTERA',
    'CASADO',
    'CASADA',
    'DIVORCIADO',
    'DIVORCIADA',
    'VIUDO',
    'VIUDA',
    'CONVIVIENTE',
    // Migration / CE document labels.
    // When ML Kit misclassifies a foreign-citizen card (Carnet de
    // Extranjería, PTP, CPP) or sees one in the same frame as a DNI,
    // these labels bleed into address extraction.
    'CARNET',
    'EXTRANJERIA',
    'MIGRACIONES',
    'PTP',
    'CPP',
    'PERMISO',
    'TEMPORAL',
    'PERMANENCIA',
    'RESOLUCION',
    // DNIe security / spec tokens (RENIEC official).
    // Printed on the back of the Peruvian electronic DNI as part of
    // the security-feature labels — never address content.
    'DNI',
    'DNIE',
    'OACI',
    'IOFE',
    'OVI',
    'JAVACARD',
    'MRZ',
    'FIRMA',
  };

  /// Maximum allowed ratio of noise tokens per line before the whole line
  /// is rejected. Hardcoded — no feature flag, by design.
  static const double _kAddressNoiseRatioThreshold = 0.4;

  /// Strips diacritics + uppercases + removes dots for denylist lookup.
  /// Mirrors [_normalizeAddressToken] but also strips accents so
  /// `VOTACIÓN` matches `VOTACION`, `DIRECCIÓN` matches `DIRECCION`, etc.
  ///
  /// Keeps Ñ — it is a real letter, not a diacritic. Some addresses have
  /// it (e.g. `BREÑA`, `CAÑETE`).
  static String _denylistKey(String token) {
    final upperNoDots = _normalizeAddressToken(token);
    return upperNoDots
        .replaceAll('Á', 'A')
        .replaceAll('É', 'E')
        .replaceAll('Í', 'I')
        .replaceAll('Ó', 'O')
        .replaceAll('Ú', 'U')
        .replaceAll('Ü', 'U');
  }

  /// Strips ALL dots and uppercases for whitelist lookup. Stripping all
  /// dots (not just leading/trailing) lets dotted compound abbreviations
  /// — `PP.JJ.` → `PPJJ`, `A.H.` → `AH`, `AA.HH.` → `AAHH`, `URB.` →
  /// `URB`, `JR.` → `JR` — collapse to a single canonical form for the
  /// whitelist lookup. Alphanumeric code checks still operate on the
  /// ORIGINAL token (where the dot is structurally meaningful), so
  /// `MZ.C` / `LT.20` are still recognised correctly.
  static String _normalizeAddressToken(String token) {
    return token.toUpperCase().replaceAll('.', '');
  }

  /// Recognises alphanumeric codes typical of Peruvian addresses: roman
  /// numerals (`I`, `II`, `III`, `IV`, …), pure or ordinal-suffixed
  /// numbers (`123`, `3ER`, `2DA`), single uppercase letters used as
  /// zone/manzana codes (`ZONA C`, `MZ. A`), letter+digit and digit+letter
  /// combos (`H15`, `220S`), and prefix-with-code combos (`MZ.C`, `LT.20`,
  /// `MZ.CL20`).
  static bool _isAlphanumericCode(String token) {
    final upper = token.toUpperCase();
    if (RegExp(r'^[IVX]{1,4}$').hasMatch(upper)) return true;
    if (RegExp(r'^\d{1,4}(?:ER|DA|TO|MO|NO|VO)?$').hasMatch(upper)) return true;
    // Single uppercase letter used as a zone/manzana code (e.g. `ZONA C`,
    // `MZ. A`). Lone letters in any other context are still rejected by
    // the per-line noise ratio because they do not contribute to overall
    // address signal density.
    if (RegExp(r'^[A-ZÑ]$').hasMatch(upper)) return true;
    if (RegExp(r'^[A-ZÑ]{1,3}\d{1,4}$').hasMatch(upper)) return true;
    if (RegExp(r'^\d{1,4}[A-ZÑ]{1,3}$').hasMatch(upper)) return true;
    if (RegExp(r'^[A-ZÑ]{1,4}\.[A-ZÑ]{0,3}\d{0,4}$').hasMatch(upper)) {
      return true;
    }
    if (RegExp(r'^[A-ZÑ]{1,4}\.\d{1,4}[A-ZÑ]{0,3}$').hasMatch(upper)) {
      return true;
    }
    return false;
  }

  /// Heuristic check that a token looks like a real Spanish word: ≥3
  /// chars, at least one vowel (Á/É/Í/Ó/Ú/Ñ accepted), no OCR-noise
  /// symbols, and a roughly sane consonant/vowel ratio. Tokens that mix
  /// digits with very few letters are rejected so they fall through to
  /// [_isAlphanumericCode].
  static bool _isLikelySpanishWord(String token) {
    if (token.length < 3) return false;
    if (RegExp(r'[<>~`|\\/]').hasMatch(token)) return false;
    if (token.contains('--')) return false;
    if (!RegExp('[AEIOUÁÉÍÓÚÑaeiouáéíóúñ]').hasMatch(token)) return false;
    final consonants = RegExp(
      '[BCDFGHJKLMNPQRSTVWXYZbcdfghjklmnpqrstvwxyz]',
    ).allMatches(token).length;
    final vowels = RegExp(
      '[AEIOUÁÉÍÓÚaeiouáéíóú]',
    ).allMatches(token).length;
    if (vowels == 0 || consonants > vowels * 3) return false;
    if (RegExp(r'\d').hasMatch(token) && token.length < 5) return false;
    return true;
  }

  /// Per-line address noise filter. Tokenises the raw line on whitespace,
  /// classifies each token (whitelist / code / Spanish-word / noise), and
  /// returns the cleaned line — or `null` if the noise ratio exceeds
  /// [_kAddressNoiseRatioThreshold] (40%) or the line lacks a structural
  /// address anchor.
  ///
  /// Public so [AddressFieldStrategy] and unit tests can call it directly
  /// without going through the full ML Kit block pipeline.
  static String? cleanAddressLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) return null;
    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.isEmpty) return null;

    final cleanTokens = <String>[];
    var noiseCount = 0;
    var contentCount = 0; // tokens that aren't pure connectors
    for (final token in tokens) {
      final normalized = _normalizeAddressToken(token);
      final denyKey = _denylistKey(token);

      // Denylist FIRST — these are real Spanish words but never address
      // content (CONSTANCIA, SUFRAGIO, VOTACION, etc.). They'd otherwise
      // pass _isLikelySpanishWord and pollute Strategy 3's output.
      if (_kAddressNoiseDenylist.contains(denyKey)) {
        noiseCount++;
        continue;
      }

      if (_kAddressPrefixes.contains(normalized)) {
        cleanTokens.add(token);
        contentCount++;
      } else if (_kAddressConnectors.contains(normalized)) {
        cleanTokens.add(token);
        // Connectors don't count as content — they're glue, not signal.
      } else if (_isAlphanumericCode(token)) {
        cleanTokens.add(token);
        contentCount++;
      } else if (_isLikelySpanishWord(token)) {
        cleanTokens.add(token);
        contentCount++;
      } else {
        noiseCount++;
      }
    }

    if (cleanTokens.isEmpty) return null;
    // A line of pure connectors (`DE`, `LA EL`, `DE LOS`) carries no
    // address signal on its own — reject so the caller's segment list
    // is built from content-bearing lines only.
    if (contentCount == 0) return null;
    final noiseRatio = noiseCount / tokens.length;
    if (noiseRatio > _kAddressNoiseRatioThreshold) return null;

    // Structural anchor guard. Survives the ratio gate but lacks any
    // address shape? Reject. Closes the person-name leak
    // (`APELLIDOS QUIROZ X` → was `QUIROZ X`) and the
    // date-fragment leak (`FECHA DE CADUCIDAD 25 03 2036` →
    // was `DE 25 03 2036`).
    if (!_hasAddressAnchor(cleanTokens)) return null;

    return cleanTokens.join(' ');
  }

  /// Structural anchor: a line that survives the noise-ratio gate must
  /// still look LIKE an address. Required: at least one recognized
  /// address prefix (`AV`, `JR`, `MZ`, `CP`, …) OR the combination of a
  /// numeric code AND a proper-noun-shaped word.
  ///
  /// Why both: pure person-names have proper nouns but no numeric code →
  /// rejected. Pure date fragments (`DE 25 03 2036`) have numeric codes
  /// but no proper noun (DE is a connector, dates are digit-only) →
  /// rejected. Real prefix-less Peruvian addresses like
  /// `SANTA ROSA 1080 MARIATEGUI` have both `1080` (numeric) and
  /// `SANTA`/`ROSA`/`MARIATEGUI` (proper nouns) → kept.
  ///
  /// Operates on the POST-noise-filter token list so that denylist tokens
  /// do not artificially supply the proper-noun signal.
  static bool _hasAddressAnchor(List<String> tokens) {
    var hasPrefix = false;
    var hasNumericCode = false;
    var hasProperNoun = false;

    for (final token in tokens) {
      final normalized = _normalizeAddressToken(token);

      if (_kAddressPrefixes.contains(normalized)) {
        hasPrefix = true;
      }

      // Numeric code: pure digits or digits with a short ordinal/letter
      // suffix (3ER, 1080, 220S). Excludes letter-led tokens.
      if (RegExp(r'^\d{1,5}[A-ZÑ]{0,3}$').hasMatch(normalized)) {
        hasNumericCode = true;
      }

      // Proper-noun shape: 3+ chars, has a vowel, NOT a connector, NOT
      // digit-led. Filters out date numbers (digit-led) and connectors
      // (DE/DEL/LA/EL/…) so they don't satisfy this branch on their own.
      if (normalized.length >= 3 &&
          !_kAddressConnectors.contains(normalized) &&
          !RegExp(r'^\d').hasMatch(normalized) &&
          RegExp('[AEIOUÁÉÍÓÚÑ]').hasMatch(normalized)) {
        hasProperNoun = true;
      }
    }

    return hasPrefix || (hasNumericCode && hasProperNoun);
  }

  /// Removes denylist tokens (`CONSTANCIA`, `SUFRAGIO`, `VOTACION`,
  /// `GRUPO`, `DIRECCION`/`DIRECCIS`/`DOMICILIO`/`DOMICILI`, …) and
  /// stranded connectors adjacent to them from BOTH the head and tail of
  /// an already-joined address.
  ///
  /// Strategy: tokenize on whitespace, walk inward from each end. Drop
  /// tokens that are in the denylist OR are connectors (`DE`, `DEL`,
  /// `LA`, `EL`, `LAS`, `LOS`, `Y`) immediately adjacent to a denylist
  /// token. Stop at the first non-denylist non-stranded-connector token.
  ///
  /// Examples:
  ///   `STA ROSA 1080 CONSTANCIA DE SUFRAGIO` → `STA ROSA 1080`
  ///   `DE SUFRAGIO DE SUFRAGIO STA ROSA 1080 MARIATEGUI` → `STA ROSA 1080 MARIATEGUI`
  ///   `STA ROSA 1080 GRUPO DE VOTACION` → `STA ROSA 1080`
  ///   `DIRECCION MZ.C LT.20` → `MZ.C LT.20`
  ///
  /// Public so [AddressFieldStrategy] and unit tests can call it directly.
  static String stripAddressLabelTail(String address) {
    if (address.trim().isEmpty) return '';
    final tokens = address.trim().split(RegExp(r'\s+'));

    bool isStrippable(String token) {
      return _kAddressNoiseDenylist.contains(_denylistKey(token));
    }

    bool isConnector(String token) {
      return _kAddressConnectors.contains(_normalizeAddressToken(token));
    }

    // Strip from head: while leading token is denylist OR is a connector
    // immediately followed by a denylist token, drop.
    var start = 0;
    while (start < tokens.length) {
      final t = tokens[start];
      if (isStrippable(t)) {
        start++;
        continue;
      }
      if (isConnector(t) &&
          start + 1 < tokens.length &&
          isStrippable(tokens[start + 1])) {
        start++;
        continue;
      }
      break;
    }

    // Strip from tail: while trailing token is denylist OR is a connector
    // immediately followed (in reverse) by a denylist token, drop.
    var end = tokens.length;
    while (end > start) {
      final t = tokens[end - 1];
      if (isStrippable(t)) {
        end--;
        continue;
      }
      if (isConnector(t) && end - 2 >= start && isStrippable(tokens[end - 2])) {
        end--;
        continue;
      }
      break;
    }

    if (start >= end) return '';
    return tokens.sublist(start, end).join(' ');
  }

  static bool _isValidAddress(String text) {
    final t = text.trim().toUpperCase();
    if (t.length < 5 || t.length > 150) return false;
    if ('<'.allMatches(t).length >= 2) return false; // MRZ-like
    if (!RegExp('[A-ZÁÉÍÓÚÑ]').hasMatch(t)) return false;
    const rejectPrefixes = [
      'DOMICILIO',
      'RENIEC',
      'REPUBLICA',
      'PERU',
      'REGISTRO',
      'NACIONAL',
      'IDENTIFICACION',
      'CONSTANCIA',
      'SUFRAGIO',
      'DECLARACION',
    ];
    return !rejectPrefixes.any(
      (p) => t == p || t.startsWith('$p ') || t.startsWith('$p.'),
    );
  }

  static bool _isPersonName(String text) {
    final clean = text.trim();
    if (clean.length < 2 || clean.length > 25) return false;
    if (clean != clean.toUpperCase()) return false;
    if (RegExp('[0-9<>/]').hasMatch(clean)) return false;
    if (!RegExp('^[A-ZÁÉÍÓÚÑ ]+\$').hasMatch(clean)) return false;

    // Reject text with too many consecutive consonants (corrupt OCR).
    if (RegExp('[BCDFGHJKLMNPQRSTVWXYZ]{4,}').hasMatch(clean)) return false;

    // Reject DNI labels (exact and partial via OCR corruption).
    const forbidden = [
      'REPUBLICA',
      'PERU',
      'REGISTRO',
      'NACIONAL',
      'IDENTIFICACION',
      'ESTADO',
      'CIVIL',
      'DOCUMENTO',
      'IDENTIDAD',
      'DNI',
      'DUPLICADO',
      'FECHA',
      'INSCRIPCION',
      'EMISION',
      'CADUCIDAD',
      'NACIMIENTO',
      'SEXO',
      'UBIGEO',
      'PRIMER',
      'SEGUNDO',
      'APELLIDO',
      'APELLIDOS',
      'NOMBRES',
      'PRENOMBRES',
      'PRE',
      'NOMBRE',
    ];
    final words = clean.split(' ');
    for (final word in words) {
      for (final f in forbidden) {
        if (word == f) return false;
      }
    }

    return true;
  }
}
