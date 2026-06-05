/// Utility for filtering address noise from OCR text lines.
///
/// Hardens address extraction against QR/barcode text artifacts
/// (`WHAPP AGE 0-- AT 220S MG`) and corrupted label tokens
/// (`DIRECCIS`, `DIRECCI`, …).
///
/// All methods are static; this class is not meant to be instantiated.
///
/// Design:
///   • Per-line noise ratio: any line with > 40% non-address tokens is
///     dropped wholesale (no partial mid-line stripping).
///   • Address-token classifier: whitelist of Peruvian address prefixes,
///     Spanish connectors, alphanumeric codes (`MZ.C`, `LT.20`, `3ER`,
///     `220S`, roman I-X), and a phonotactic-shaped "likely Spanish word"
///     check.
///   • Label-tail strip: removes corrupted `DIRECC*` / `DOMICIL*` tokens
///     from BOTH head and tail of the joined address.
final class AddressNoiseFilter {
  const AddressNoiseFilter._();

  /// Peruvian address prefix whitelist. Tokens are kept regardless of
  /// length. All entries are stored with dots stripped (matching the
  /// dot-stripping behaviour of [_normalizeToken]) so dotted
  /// compound abbreviations like `PP.JJ.`, `A.H.`, `AA.HH.` are matched.
  static const kAddressPrefixes = <String>{
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
  static const kAddressConnectors = <String>{
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
  static const kAddressNoiseDenylist = <String>{
    // Voting / civic boxes
    'CONSTANCIA',
    'SUFRAGIO',
    'VOTACION', // also catches VOTACIÓN after diacritic strip
    'GRUPO',
    'MESA',
    'ELECCIONES',
    'ELECTORAL',
    'DOMICILIO',
    // `DIRECCION` is denylisted as a TOKEN to prevent stray copies of the
    // label from polluting joined address lines (e.g. ML Kit emitting
    // `MZ.C LT.20 DIRECCION`). The label as a LINE anchor is recognised
    // separately by [AddressFieldStrategy] before the noise filter runs,
    // so this entry does not block label-based extraction.
    'DIRECCION', // matches DIRECCIÓN after diacritic strip
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
  static const double kNoiseRatioThreshold = 0.4;

  /// Per-line address noise filter. Tokenises the raw line on whitespace,
  /// classifies each token (whitelist / code / Spanish-word / noise), and
  /// returns the cleaned line — or `null` if the noise ratio exceeds
  /// [kNoiseRatioThreshold] (40%) or the line lacks a structural
  /// address anchor.
  static String? cleanAddressLine(String rawLine) {
    final trimmed = rawLine.trim();
    if (trimmed.isEmpty) return null;
    final tokens = trimmed.split(RegExp(r'\s+'));
    if (tokens.isEmpty) return null;

    final cleanTokens = <String>[];
    var noiseCount = 0;
    var contentCount = 0;
    for (final token in tokens) {
      final normalized = _normalizeToken(token);
      final denyKey = _denylistKey(token);

      if (kAddressNoiseDenylist.contains(denyKey)) {
        noiseCount++;
        continue;
      }

      if (kAddressPrefixes.contains(normalized)) {
        cleanTokens.add(token);
        contentCount++;
      } else if (kAddressConnectors.contains(normalized)) {
        cleanTokens.add(token);
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
    if (contentCount == 0) return null;
    final noiseRatio = noiseCount / tokens.length;
    if (noiseRatio > kNoiseRatioThreshold) return null;
    if (!_hasAddressAnchor(cleanTokens)) return null;

    return cleanTokens.join(' ');
  }

  /// Removes denylist tokens and stranded connectors from BOTH the head
  /// and tail of an already-joined address.
  static String stripAddressLabelTail(String address) {
    if (address.trim().isEmpty) return '';
    final tokens = address.trim().split(RegExp(r'\s+'));

    bool isStrippable(String token) =>
        kAddressNoiseDenylist.contains(_denylistKey(token));

    bool isConnector(String token) =>
        kAddressConnectors.contains(_normalizeToken(token));

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

  // ── Private helpers ───────────────────────────────────────────────────

  /// Strips ALL dots and uppercases for whitelist lookup.
  static String _normalizeToken(String token) =>
      token.toUpperCase().replaceAll('.', '');

  /// Strips diacritics + uppercases + removes dots for denylist lookup.
  static String _denylistKey(String token) => _normalizeToken(token)
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U');

  /// Recognises alphanumeric codes typical of Peruvian addresses.
  static bool _isAlphanumericCode(String token) {
    final upper = token.toUpperCase();
    if (RegExp(r'^[IVX]{1,4}$').hasMatch(upper)) return true;
    if (RegExp(r'^\d{1,4}(?:ER|DA|TO|MO|NO|VO)?$').hasMatch(upper)) return true;
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

  /// Heuristic check that a token looks like a real Spanish word.
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

  /// Structural anchor: a cleaned line must look LIKE an address.
  static bool _hasAddressAnchor(List<String> tokens) {
    var hasPrefix = false;
    var hasNumericCode = false;
    var hasProperNoun = false;

    for (final token in tokens) {
      final normalized = _normalizeToken(token);

      if (kAddressPrefixes.contains(normalized)) {
        hasPrefix = true;
      }

      if (RegExp(r'^\d{1,5}[A-ZÑ]{0,3}$').hasMatch(normalized)) {
        hasNumericCode = true;
      }

      if (normalized.length >= 3 &&
          !kAddressConnectors.contains(normalized) &&
          !RegExp(r'^\d').hasMatch(normalized) &&
          RegExp('[AEIOUÁÉÍÓÚÑ]').hasMatch(normalized)) {
        hasProperNoun = true;
      }
    }

    return hasPrefix || (hasNumericCode && hasProperNoun);
  }
}
