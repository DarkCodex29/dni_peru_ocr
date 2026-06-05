import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/address_noise_filter.dart';
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

    // Strategy 1 — explicit label anchor (`DOMICILIO` / `DIRECCIÓN` family).
    //
    // The booklet-style DNI prints `DOMICILIO`; the electronic DNI prints
    // `Dirección` (Spanish accent, possibly with colon). We accept both
    // spellings plus the abbreviated `DOM` / `DOM.` forms used by some
    // older issuers.
    final isDomicilioAnchor = upper.contains('DOMICILIO') ||
        upper.startsWith('DOM ') ||
        upper == 'DOM.';
    final isDireccionAnchor = upper.contains('DIRECCIÓN') ||
        upper.contains('DIRECCION');
    if (isDomicilioAnchor || isDireccionAnchor) {
      final inlineValue = upper
          .replaceAll(RegExp(r'DOMICILIO\.?:?\s*'), '')
          .replaceAll(RegExp(r'DIRECCI[ÓO]N\.?:?\s*'), '')
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
        final cleaned = AddressNoiseFilter.cleanAddressLine(candidate);
        if (cleaned == null) continue;
        if (_hasAddressPrefix(cleaned) ||
            _isAddressContinuation(cleaned) ||
            _isValidAddress(cleaned)) {
          segments.add(cleaned);
        }
      }
      if (segments.isNotEmpty) {
        final joined = segments.join(' ');
        final stripped = AddressNoiseFilter.stripAddressLabelTail(joined);
        result.address = stripped.isEmpty ? null : stripped;
        return;
      }
    }
  }

  /// Funnels a raw recovered address through [AddressNoiseFilter.cleanAddressLine] and
  /// [AddressNoiseFilter.stripAddressLabelTail] before assigning.
  void _assignFilteredAddress(
    OcrExtractedFields result,
    String rawAddress,
  ) {
    final cleaned = AddressNoiseFilter.cleanAddressLine(rawAddress);
    if (cleaned == null) return;
    final stripped = AddressNoiseFilter.stripAddressLabelTail(cleaned);
    if (stripped.isEmpty) return;
    result.address = stripped;
  }

  /// Builds the address string starting at [startIdx], collecting up to 3
  /// additional lines while they look like address continuations.
  ///
  /// Three independent rules attach a candidate line:
  ///
  ///   1. **Prefixed continuation** — line starts with a known continuation
  ///      prefix (`MZ.`, `LT.`, `MZA.`, `LTE.`, `NRO.`, `INT.`, `DPTO.`,
  ///      and their bare-space variants).
  ///   2. **Prefixed address** — line starts with a known street prefix
  ///      (`AV.`, `JR.`, `CALLE`, `PSJ.`, `URB.`, …).
  ///   3. **Dangling anchor recovery** — the previous line ended with an
  ///      orphan anchor token (a bare `MZ`/`LT`/`NRO` without its value),
  ///      and the next line carries the missing tail (e.g. `B LT.19` or
  ///      `19`). ML Kit occasionally splits `MZ.B LT.19` across two visual
  ///      lines depending on document tilt and lighting, so the tail line
  ///      cannot rely on a prefix match.
  ///
  /// Rule 3 is gated by [_looksLikeContinuationFragment] which enforces a
  /// 30-character cap and a label denylist so unrelated content does not
  /// get stitched into the address.
  String _buildAddress(List<String> lines, int startIdx) {
    final parts = <String>[lines[startIdx].trim().toUpperCase()];
    for (int j = startIdx + 1; j < lines.length && j <= startIdx + 3; j++) {
      final next = lines[j].trim().toUpperCase();
      if (next.isEmpty) break;
      final prev = parts.last;
      if (_isAddressContinuation(next) ||
          _hasAddressPrefix(next) ||
          _looksLikeContinuationFragment(prev, next)) {
        parts.add(next);
      } else {
        break;
      }
    }
    return parts.join(' ');
  }

  /// Detects an OCR-split continuation: previous line ends with a bare
  /// continuation anchor (`MZ`, `LT`, `NRO`, `INT`, `DPTO`, `MZA`, `LTE`)
  /// or a trailing dot/period, and the next line carries the missing value
  /// (a single alphanumeric token, a `B LT.19`-shaped tail, etc.).
  bool _looksLikeContinuationFragment(String prev, String next) {
    if (prev.isEmpty || next.isEmpty) return false;
    // Strip trailing dot for the tail check (`MZ.` ↔ `MZ`).
    final prevTail = prev
        .split(RegExp(r'\s+'))
        .last
        .replaceAll(RegExp(r'\.+$'), '');
    const danglingAnchors = {
      'MZ', 'MZA',
      'LT', 'LTE',
      'NRO',
      'INT',
      'DPTO',
    };
    if (!danglingAnchors.contains(prevTail)) return false;
    // The next line must look like an address fragment: short tokens,
    // letters/numbers/dots only, ≤ 30 chars. Reject obvious labels.
    if (next.length > 30) return false;
    if (!RegExp(r'^[A-Z0-9. ]+$').hasMatch(next)) return false;
    if (RegExp(r'^(DIRECCI|DOMICILI|DEPARTAMENT|PROVIN|DISTRIT|UBIGEO|GRUPO|VOTACI|DONACI|ORGANO|SANGUINE|FECHA|CADUC|NACIM|SEXO|NACIONAL)').hasMatch(next)) {
      return false;
    }
    return true;
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
      'MZA.',
      'MZA ',
      'LT.',
      'LT ',
      'LTE.',
      'LTE ',
      'NRO.',
      'NRO ',
      'INT.',
      'DPTO.',
      'INT ',
      'DPTO ',
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
