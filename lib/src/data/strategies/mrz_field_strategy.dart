import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_parser/mrz_parser.dart';

import '../../data/ocr_field_extractor.dart';
import 'ocr_field_strategy.dart';

/// Strategy that extracts OCR fields from a Machine Readable Zone (MRZ).
///
/// Supports both TD1 (3 lines × 30 chars) and TD3 (2 lines × 44 chars)
/// formats used on Peruvian DNIs.
///
/// Returns `null` when no valid MRZ block is found in the [RecognizedText].
/// When successful, [OcrExtractedFields.hasMrzData] is `true` and [address]
/// is always `null` (address data is never present in MRZ).
final class MrzFieldStrategy implements OcrFieldStrategy {
  const MrzFieldStrategy();

  @override
  OcrExtractedFields? extract(RecognizedText recognized) {
    if (recognized.blocks.isEmpty) return null;
    return _tryParseMrz(recognized);
  }

  /// Attempts to locate and parse MRZ lines from [recognized].
  /// Returns `null` when no valid MRZ is found.
  OcrExtractedFields? _tryParseMrz(RecognizedText recognized) {
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

  bool _looksLikeMrz(String line) {
    final mrzChars = RegExp('[A-Z0-9<]');
    final mrzCount = mrzChars.allMatches(line).length;
    return mrzCount > line.length * 0.8;
  }

  OcrExtractedFields? _tryParseLines(List<String> lines) {
    try {
      final result = MRZParser.tryParse(lines);
      if (result == null) return null;

      final fields = OcrExtractedFields()
        ..markAsMrzSourced = true
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
}
