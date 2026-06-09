import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/address_noise_filter.dart';
import '../../data/ocr_field_extractor.dart';
import 'ocr_field_strategy.dart';

/// Strategy that extracts address and ubigeo fields from OCR text blocks.
final class AddressFieldStrategy implements OcrFieldStrategy {
  const AddressFieldStrategy();

  @override
  OcrExtractedFields? extract(RecognizedText recognized) {
    if (recognized.blocks.isEmpty) return null;

    final result = OcrExtractedFields();
    _extractAddressFromBlocks(recognized, result);

    final hasAnyField = result.address != null ||
        result.department != null ||
        result.province != null ||
        result.district != null;
    return hasAnyField ? result : null;
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
      if (result.address == null) {
        _tryExtractAddress(lines, i, result);
      }
      _tryExtractUbigeo(lines[i], result);
    }
  }

  void _tryExtractUbigeo(String line, OcrExtractedFields result) {
    if (result.department != null &&
        result.province != null &&
        result.district != null) {
      return;
    }
    final trimmed = line.trim().toUpperCase();
    if (!_isUbigeoLine(trimmed)) return;
    if (RegExp(r'\b(DEPARTAMENTO|PROVINCIA|DISTRITO)\b').hasMatch(trimmed)) {
      return;
    }

    final parts = trimmed
        .split('/')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.length == 3) {
      result.department ??= parts[0];
      result.province ??= parts[1];
      result.district ??= parts[2];
    } else if (parts.length == 2) {
      result.department ??= parts[0];
      result.district ??= parts[1];
    }
  }

  bool _looksLikeMrzLine(String line) {
    final clean = line.replaceAll(' ', '');
    return clean.length >= 20 && '<'.allMatches(clean).length >= 3;
  }

  void _tryExtractAddress(
    List<String> lines,
    int i,
    OcrExtractedFields result,
  ) {
    if (result.address != null) return;
    final upper = lines[i].toUpperCase().trim();

    final isDomicilioAnchor = upper.contains('DOMICILIO') ||
        upper.startsWith('DOM ') ||
        upper == 'DOM.';
    final isDireccionAnchor =
        upper.contains('DIRECCIÓN') || upper.contains('DIRECCION');
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

    if (_hasAddressPrefix(upper)) {
      _assignFilteredAddress(result, _buildAddress(lines, i));
      return;
    }

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

  bool _looksLikeContinuationFragment(String prev, String next) {
    if (prev.isEmpty || next.isEmpty) return false;
    final prevTail =
        prev.split(RegExp(r'\s+')).last.replaceAll(RegExp(r'\.+$'), '');
    const danglingAnchors = {
      'MZ',
      'MZA',
      'LT',
      'LTE',
      'NRO',
      'INT',
      'DPTO',
    };
    if (!danglingAnchors.contains(prevTail)) return false;
    if (next.length > 30) return false;
    if (!RegExp(r'^[A-Z0-9. ]+$').hasMatch(next)) return false;
    if (RegExp(
            r'^(DIRECCI|DOMICILI|DEPARTAMENT|PROVIN|DISTRIT|UBIGEO|GRUPO|VOTACI|DONACI|ORGANO|SANGUINE|FECHA|CADUC|NACIM|SEXO|NACIONAL)')
        .hasMatch(next)) {
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
