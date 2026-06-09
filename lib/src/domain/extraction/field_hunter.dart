import '../../data/field_value_cleaner.dart';
import '../../data/ocr_text_sanitizer.dart';
import '../../infrastructure/dni_logger.dart';
import '../../extraction/address_extractor.dart';
import '../../extraction/date_field_extractor.dart';
import '../../extraction/dni_number_extractor.dart';
import '../../extraction/donacion_extractor.dart';
import '../../extraction/given_names_extractor.dart';
import '../../extraction/grupo_votacion_extractor.dart';
import '../../extraction/mrz_extractor.dart';
import '../../extraction/nationality_extractor.dart';
import '../../extraction/sex_extractor.dart';
import '../../extraction/state_civil_extractor.dart';
import '../../extraction/surname_extractor.dart';
import '../../extraction/tarjeta_extractor.dart';
import '../../extraction/ubigeo_extractor.dart';
import '../../extraction/ubigeo_nacimiento_extractor.dart';
import '../entities/dni_format.dart';
import '../entities/document_side.dart';
import '_extractor_filter.dart';
import 'dni_field.dart';
import 'dni_fields.dart';
import 'extracted_fields.dart';
import 'field_extractor.dart';
import 'hunt_result.dart';

class FieldHunter {
  FieldHunter({
    required this.extractors,
    DniFields? fields,
    DocumentSideDetector sideDetector = const DocumentSideDetector(),
    DniFormatDetector formatDetector = const DniFormatDetector(),
    OcrTextSanitizer sanitizer = const OcrTextSanitizer(),
    FieldValueCleaner valueCleaner = const FieldValueCleaner(),
  })  : _fields = fields,
        _sideDetector = sideDetector,
        _formatDetector = formatDetector,
        _sanitizer = sanitizer,
        _valueCleaner = valueCleaner;

  factory FieldHunter.standard({DniFields? fields}) {
    const all = [
      MrzExtractor(),
      DniNumberExtractor(),
      SurnameExtractor(),
      GivenNamesExtractor(),
      DateFieldExtractor(),
      SexExtractor(),
      NationalityExtractor(),
      AddressExtractor(),
      UbigeoExtractor(),
      StateCivilExtractor(),
      TarjetaExtractor(),
      DonacionExtractor(),
      GrupoVotacionExtractor(),
      UbigeoNacimientoExtractor(),
    ];
    return FieldHunter(
      extractors: filteredExtractors(fields, all),
      fields: fields,
    );
  }

  final List<FieldExtractor> extractors;
  final DniFields? _fields;
  final DocumentSideDetector _sideDetector;
  final DniFormatDetector _formatDetector;
  final OcrTextSanitizer _sanitizer;
  final FieldValueCleaner _valueCleaner;

  final Map<_FieldKey, Map<String, _Vote>> _votes = {};
  bool _frontDetected = false;
  bool _backDetected = false;
  DocumentSide _lastSeen = DocumentSide.unknown;
  DniFormat _format = DniFormat.unknown;

  HuntResult get snapshot {
    final fields = ExtractedFields();
    for (final entry in _votes.entries) {
      final winner = _winnerOf(entry.value);
      if (winner == null) continue;
      _assignField(fields, entry.key, winner);
    }
    _reconcileSurnames(fields);
    return HuntResult(
      fields: fields,
      frontDetected: _frontDetected,
      backDetected: _backDetected,
      lastSeen: _lastSeen,
      format: _format,
    );
  }

  bool process(String recognizedText) {
    if (recognizedText.isEmpty) return false;
    final detected = _sideDetector.detect(recognizedText);
    if (detected != DocumentSide.unknown) {
      _lastSeen = detected;
      if (detected == DocumentSide.front) _frontDetected = true;
      if (detected == DocumentSide.back) _backDetected = true;
    }
    if (_format == DniFormat.unknown) {
      final detectedFormat = _formatDetector.detect(recognizedText);
      if (detectedFormat != DniFormat.unknown) _format = detectedFormat;
    }
    final cleaned = _sanitizer.sanitize(recognizedText);
    if (cleaned.isEmpty) {
      DniLogger.debug('FieldHunter', 'sanitizer dropped all text');
      return false;
    }

    var addedNew = false;
    for (final extractor in extractors) {
      final partial = extractor.extract(cleaned);
      _logPartial(extractor, partial);
      addedNew = _vote(_FieldKey.documentNumber, partial.documentNumber) ||
          addedNew;
      addedNew = _vote(_FieldKey.firstName, partial.firstName) || addedNew;
      addedNew = _vote(_FieldKey.lastName, partial.lastName) || addedNew;
      addedNew = _vote(_FieldKey.secondLastName, partial.secondLastName) ||
          addedNew;
      addedNew =
          _vote(_FieldKey.dateOfBirth, partial.dateOfBirth) || addedNew;
      addedNew =
          _vote(_FieldKey.expirationDate, partial.expirationDate) || addedNew;
      addedNew =
          _vote(_FieldKey.emissionDate, partial.emissionDate) || addedNew;
      addedNew =
          _vote(_FieldKey.inscriptionDate, partial.inscriptionDate) || addedNew;
      addedNew = _vote(_FieldKey.sex, partial.sex) || addedNew;
      addedNew =
          _vote(_FieldKey.nationality, partial.nationality) || addedNew;
      addedNew = _vote(_FieldKey.address, partial.address) || addedNew;
      addedNew =
          _vote(_FieldKey.department, partial.department) || addedNew;
      addedNew = _vote(_FieldKey.province, partial.province) || addedNew;
      addedNew = _vote(_FieldKey.district, partial.district) || addedNew;
      addedNew = _vote(_FieldKey.stateCivil, partial.stateCivil) || addedNew;
      addedNew = _vote(_FieldKey.cardNumber, partial.cardNumber) || addedNew;
      addedNew = _vote(_FieldKey.organDonor, partial.organDonor) || addedNew;
      addedNew = _vote(_FieldKey.votingGroup, partial.votingGroup) || addedNew;
      addedNew = _vote(_FieldKey.birthUbigeoCode, partial.birthUbigeoCode) ||
          addedNew;
    }
    return addedNew;
  }

  void reset() {
    _votes.clear();
    _frontDetected = false;
    _backDetected = false;
    _lastSeen = DocumentSide.unknown;
    _format = DniFormat.unknown;
  }

  bool _vote(_FieldKey key, String? value) {
    if (_fields != null) {
      final dniField = _fieldKeyToDniField[key];
      if (dniField != null && !_fields!.contains(dniField)) return false;
    }
    final cleaned = _shouldClean(key) ? _valueCleaner.clean(value) : value;
    if (cleaned == null || cleaned.isEmpty) return false;
    final normalized = _normalize(cleaned);
    if (_isCrossFieldCollision(key, normalized)) {
      DniLogger.debug(
        'FieldHunter',
        'REJECT ${key.name} = "$cleaned" (collides with another field)',
      );
      return false;
    }
    final bucket = _votes.putIfAbsent(key, () => {});
    final existing = bucket[normalized];
    if (existing == null) {
      bucket[normalized] = _Vote(display: cleaned, count: 1);
      DniLogger.info(
        'FieldHunter',
        'NEW ${key.name} = "$cleaned" (vote 1)',
      );
      return true;
    }
    existing.count++;
    if (_preferDisplay(key, existing.display, cleaned)) {
      existing.display = cleaned;
    }
    DniLogger.debug(
      'FieldHunter',
      '+1 ${key.name} = "${existing.display}" (votes=${existing.count})',
    );
    return false;
  }

  bool _isCrossFieldCollision(_FieldKey key, String normalized) {
    if (key != _FieldKey.firstName) return false;
    const forbidden = {
      'DUPLICADO',
      'APELLIDOS',
      'PRENOMBRES',
      'PRE NOMBRES',
      'NOMBRES',
      'REPUBLICA DEL PERU',
      'DOCUMENTO NACIONAL DE IDENTIDAD',
      'REGISTRO NACIONAL DE IDENTIFICACION Y ESTADO CIVIL',
    };
    if (forbidden.contains(normalized)) return true;
    final lastBucket = _votes[_FieldKey.lastName];
    final secondBucket = _votes[_FieldKey.secondLastName];
    final lastWinner = lastBucket == null ? null : _winnerOf(lastBucket);
    final secondWinner =
        secondBucket == null ? null : _winnerOf(secondBucket);
    if (lastWinner != null && _normalize(lastWinner) == normalized) {
      return true;
    }
    if (secondWinner != null && _normalize(secondWinner) == normalized) {
      return true;
    }
    if (lastWinner != null && secondWinner != null) {
      final combined = _normalize('$lastWinner $secondWinner');
      if (combined == normalized) return true;
    }
    return false;
  }

  void _logPartial(FieldExtractor extractor, ExtractedFields p) {
    if (!DniLogger.isEnabled) return;
    final found = <String>[];
    if (p.documentNumber != null) found.add('docNum=${p.documentNumber}');
    if (p.firstName != null) found.add('firstName=${p.firstName}');
    if (p.lastName != null) found.add('lastName=${p.lastName}');
    if (p.secondLastName != null) {
      found.add('secondLastName=${p.secondLastName}');
    }
    if (p.dateOfBirth != null) found.add('birth=${p.dateOfBirth}');
    if (p.expirationDate != null) found.add('exp=${p.expirationDate}');
    if (p.emissionDate != null) found.add('emission=${p.emissionDate}');
    if (p.inscriptionDate != null) {
      found.add('inscription=${p.inscriptionDate}');
    }
    if (p.sex != null) found.add('sex=${p.sex}');
    if (p.nationality != null) found.add('nat=${p.nationality}');
    if (p.address != null) found.add('addr=${p.address}');
    if (p.department != null) found.add('dep=${p.department}');
    if (p.province != null) found.add('prov=${p.province}');
    if (p.district != null) found.add('dist=${p.district}');
    if (p.stateCivil != null) found.add('stateCivil=${p.stateCivil}');
    if (p.cardNumber != null) found.add('card=${p.cardNumber}');
    if (p.organDonor != null) found.add('donor=${p.organDonor}');
    if (p.votingGroup != null) found.add('vGroup=${p.votingGroup}');
    if (p.birthUbigeoCode != null) {
      found.add('birthUbigeo=${p.birthUbigeoCode}');
    }
    if (found.isEmpty) return;
    DniLogger.debug(
      'FieldHunter',
      '${extractor.runtimeType} -> ${found.join(', ')}',
    );
  }

  bool _shouldClean(_FieldKey key) {
    switch (key) {
      case _FieldKey.documentNumber:
      case _FieldKey.dateOfBirth:
      case _FieldKey.expirationDate:
      case _FieldKey.emissionDate:
      case _FieldKey.inscriptionDate:
      case _FieldKey.sex:
      case _FieldKey.cardNumber:
      case _FieldKey.organDonor:
      case _FieldKey.votingGroup:
      case _FieldKey.birthUbigeoCode:
      case _FieldKey.stateCivil:
        return false;
      case _FieldKey.firstName:
      case _FieldKey.lastName:
      case _FieldKey.secondLastName:
      case _FieldKey.nationality:
      case _FieldKey.address:
      case _FieldKey.department:
      case _FieldKey.province:
      case _FieldKey.district:
        return true;
    }
  }

  String? _winnerOf(Map<String, _Vote> bucket) {
    if (bucket.isEmpty) return null;
    _Vote? best;
    for (final vote in bucket.values) {
      if (best == null || vote.count > best.count) best = vote;
    }
    return best?.display;
  }

  String _normalize(String value) {
    return value
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÄÂÃ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈËÊ]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÏÎ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÖÔÕ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÜÛ]'), 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll('NH', 'N')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _preferDisplay(_FieldKey key, String current, String incoming) {
    if (_prefersNoDiacritics(key)) {
      final currentDiacritics = _countDiacritics(current);
      final incomingDiacritics = _countDiacritics(incoming);
      return incomingDiacritics < currentDiacritics;
    }
    return false;
  }

  bool _prefersNoDiacritics(_FieldKey key) {
    switch (key) {
      case _FieldKey.department:
      case _FieldKey.province:
      case _FieldKey.district:
      case _FieldKey.address:
      case _FieldKey.firstName:
      case _FieldKey.lastName:
      case _FieldKey.secondLastName:
        return true;
      default:
        return false;
    }
  }

  int _countDiacritics(String value) {
    return RegExp(r'[ÁÉÍÓÚÑáéíóúñ]').allMatches(value).length;
  }

  void _reconcileSurnames(ExtractedFields fields) {
    final paternal = fields.lastName;
    final maternal = fields.secondLastName;
    if (paternal == null) return;
    final paternalParts = paternal.split(' ');
    if (paternalParts.length < 2) return;
    if (maternal != null && maternal.isNotEmpty) return;
    fields
      ..lastName = paternalParts.first
      ..secondLastName = paternalParts.sublist(1).join(' ');
  }

  void _assignField(ExtractedFields fields, _FieldKey key, String value) {
    switch (key) {
      case _FieldKey.documentNumber:
        fields.documentNumber = value;
      case _FieldKey.firstName:
        fields.firstName = value;
      case _FieldKey.lastName:
        fields.lastName = value;
      case _FieldKey.secondLastName:
        fields.secondLastName = value;
      case _FieldKey.dateOfBirth:
        fields.dateOfBirth = value;
      case _FieldKey.expirationDate:
        fields.expirationDate = value;
      case _FieldKey.emissionDate:
        fields.emissionDate = value;
      case _FieldKey.inscriptionDate:
        fields.inscriptionDate = value;
      case _FieldKey.sex:
        fields.sex = value;
      case _FieldKey.nationality:
        fields.nationality = value;
      case _FieldKey.address:
        fields.address = value;
      case _FieldKey.department:
        fields.department = value;
      case _FieldKey.province:
        fields.province = value;
      case _FieldKey.district:
        fields.district = value;
      case _FieldKey.stateCivil:
        fields.stateCivil = value;
      case _FieldKey.cardNumber:
        fields.cardNumber = value;
      case _FieldKey.organDonor:
        fields.organDonor = value;
      case _FieldKey.votingGroup:
        fields.votingGroup = value;
      case _FieldKey.birthUbigeoCode:
        fields.birthUbigeoCode = value;
    }
  }
}

enum _FieldKey {
  documentNumber,
  firstName,
  lastName,
  secondLastName,
  dateOfBirth,
  expirationDate,
  emissionDate,
  inscriptionDate,
  sex,
  nationality,
  address,
  department,
  province,
  district,
  stateCivil,
  cardNumber,
  organDonor,
  votingGroup,
  birthUbigeoCode,
}

const _fieldKeyToDniField = <_FieldKey, DniField>{
  _FieldKey.documentNumber: DniField.documentNumber,
  _FieldKey.firstName: DniField.firstName,
  _FieldKey.lastName: DniField.lastName,
  _FieldKey.secondLastName: DniField.secondLastName,
  _FieldKey.dateOfBirth: DniField.dateOfBirth,
  _FieldKey.expirationDate: DniField.expirationDate,
  _FieldKey.emissionDate: DniField.emissionDate,
  _FieldKey.inscriptionDate: DniField.inscriptionDate,
  _FieldKey.sex: DniField.sex,
  _FieldKey.nationality: DniField.nationality,
  _FieldKey.address: DniField.address,
  _FieldKey.department: DniField.department,
  _FieldKey.province: DniField.province,
  _FieldKey.district: DniField.district,
  _FieldKey.stateCivil: DniField.stateCivil,
  _FieldKey.cardNumber: DniField.cardNumber,
  _FieldKey.organDonor: DniField.organDonor,
  _FieldKey.votingGroup: DniField.votingGroup,
  _FieldKey.birthUbigeoCode: DniField.birthUbigeoCode,
};

class _Vote {
  _Vote({required this.display, required this.count});
  String display;
  int count;
}
