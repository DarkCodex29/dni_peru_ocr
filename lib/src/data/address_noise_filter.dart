/// Utility for filtering address noise from OCR text lines.
final class AddressNoiseFilter {
  const AddressNoiseFilter._();

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
    'CP', 'CPM',
    'CC', 'CCNN',
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

  static const kAddressConnectors = <String>{
    'DE',
    'DEL',
    'LA',
    'EL',
    'LAS',
    'LOS',
    'Y',
  };

  static const kAddressNoiseDenylist = <String>{
    'CONSTANCIA',
    'SUFRAGIO',
    'VOTACION',
    'GRUPO',
    'MESA',
    'ELECCIONES',
    'ELECTORAL',
    'DOMICILIO',
    'DIRECCION',
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
    'RENIEC',
    'REPUBLICA',
    'REGISTRO',
    'IDENTIFICACION',
    'ESTADO',
    'CIVIL',
    'SEXO',
    'DIRECCIS',
    'DIRECCI',
    'DIREC',
    'DOMICILI',
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
    'CARNET',
    'EXTRANJERIA',
    'MIGRACIONES',
    'PTP',
    'CPP',
    'PERMISO',
    'TEMPORAL',
    'PERMANENCIA',
    'RESOLUCION',
    'DNI',
    'DNIE',
    'OACI',
    'IOFE',
    'OVI',
    'JAVACARD',
    'MRZ',
    'FIRMA',
  };

  static const double kNoiseRatioThreshold = 0.4;

  /// Per-line address noise filter. Returns `null` when the line lacks an
  /// address anchor or the noise ratio exceeds [kNoiseRatioThreshold].
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

  /// Removes denylist tokens and stranded connectors from head and tail.
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

  static String _normalizeToken(String token) =>
      token.toUpperCase().replaceAll('.', '');

  static String _denylistKey(String token) => _normalizeToken(token)
      .replaceAll('Á', 'A')
      .replaceAll('É', 'E')
      .replaceAll('Í', 'I')
      .replaceAll('Ó', 'O')
      .replaceAll('Ú', 'U')
      .replaceAll('Ü', 'U');

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
