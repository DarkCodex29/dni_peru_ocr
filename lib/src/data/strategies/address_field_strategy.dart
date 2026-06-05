import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/ocr_field_extractor.dart';
import 'ocr_field_strategy.dart';

/// Strategy that extracts address from OCR text blocks.
///
/// Implements three address-detection strategies in order:
///   1. `DOMICILIO` label — value inline or on next lines.
///   2. Peruvian address prefix (`ASEN`, `AV.`, `JR.`, `CALLE`, …) — direct content.
///   3. Ubigeo anchor (`DEPT/PROV/DIST`) — address is 1–4 lines above.
///
/// All non-address fields on the returned [OcrExtractedFields] are `null`.
/// Returns `null` when no address signal is found.
final class AddressFieldStrategy implements OcrFieldStrategy {
  const AddressFieldStrategy();

  @override
  OcrExtractedFields? extract(RecognizedText recognized) {
    if (recognized.blocks.isEmpty) return null;

    final result = OcrExtractedFields();
    _extractAddressFromBlocks(recognized, result);

    return result.address != null ? result : null;
  }

  void _extractAddressFromBlocks(
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

  /// Returns true when a single OCR line looks like a MRZ line.
  bool _looksLikeMrzLine(String line) {
    final clean = line.replaceAll(' ', '');
    return clean.length >= 20 && '<'.allMatches(clean).length >= 3;
  }

  /// Three strategies, tried in order:
  ///   1. `DOMICILIO` label — value inline or on next lines.
  ///   2. Peruvian address prefix (`ASEN`, `AV.`, `JR.`, `CALLE`, …) — direct content.
  ///   3. Ubigeo anchor (`DEPT/PROV/DIST`) — address is 1-3 lines above.
  void _tryExtractAddress(
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

    // Strategy 3: Ubigeo line as anchor.
    if (_isUbigeoLine(upper)) {
      final segments = <String>[];
      for (int offset = 4; offset >= 1; offset--) {
        final idx = i - offset;
        if (idx < 0) continue;
        final candidate = lines[idx].trim().toUpperCase();
        final cleaned = OcrFieldExtractor.cleanAddressLine(candidate);
        if (cleaned == null) continue;
        if (_hasAddressPrefix(cleaned) ||
            _isAddressContinuation(cleaned) ||
            _isValidAddress(cleaned)) {
          segments.add(cleaned);
        }
      }
      if (segments.isNotEmpty) {
        final joined = segments.join(' ');
        final stripped = OcrFieldExtractor.stripAddressLabelTail(joined);
        result.address = stripped.isEmpty ? null : stripped;
        return;
      }
    }
  }

  /// Funnels a raw recovered address through [OcrFieldExtractor.cleanAddressLine] and
  /// [OcrFieldExtractor.stripAddressLabelTail] before assigning.
  void _assignFilteredAddress(
    OcrExtractedFields result,
    String rawAddress,
  ) {
    final cleaned = OcrFieldExtractor.cleanAddressLine(rawAddress);
    if (cleaned == null) return;
    final stripped = OcrFieldExtractor.stripAddressLabelTail(cleaned);
    if (stripped.isEmpty) return;
    result.address = stripped;
  }

  /// Builds the address string starting at [startIdx], collecting up to 3
  /// additional lines while they look like address continuations.
  String _buildAddress(List<String> lines, int startIdx) {
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

  bool _hasAddressPrefix(String upper) {
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
    if (upper.startsWith('ASEN') && upper.length > 4) return true;
    return false;
  }

  bool _isAddressContinuation(String upper) {
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

  bool _isUbigeoLine(String upper) => RegExp(
    r'^/?[A-ZÁÉÍÓÚÑ\s]+(?:/[A-ZÁÉÍÓÚÑ\s]+){1,3}$',
  ).hasMatch(upper);

  bool _isValidAddress(String text) {
    final t = text.trim().toUpperCase();
    if (t.length < 5 || t.length > 150) return false;
    if ('<'.allMatches(t).length >= 2) return false;
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
}
