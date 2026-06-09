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
import 'dni_field.dart';
import 'dni_fields.dart';
import 'field_extractor.dart';

const _extractorFields = <Type, Set<DniField>>{
  MrzExtractor: {
    DniField.documentNumber,
    DniField.firstName,
    DniField.lastName,
    DniField.secondLastName,
    DniField.dateOfBirth,
    DniField.expirationDate,
    DniField.sex,
    DniField.nationality,
  },
  DniNumberExtractor: {DniField.documentNumber},
  SurnameExtractor: {DniField.lastName, DniField.secondLastName},
  GivenNamesExtractor: {DniField.firstName},
  DateFieldExtractor: {
    DniField.dateOfBirth,
    DniField.expirationDate,
    DniField.emissionDate,
    DniField.inscriptionDate,
  },
  SexExtractor: {DniField.sex},
  NationalityExtractor: {DniField.nationality},
  AddressExtractor: {DniField.address},
  UbigeoExtractor: {DniField.department, DniField.province, DniField.district},
  StateCivilExtractor: {DniField.stateCivil},
  TarjetaExtractor: {DniField.cardNumber},
  DonacionExtractor: {DniField.organDonor},
  GrupoVotacionExtractor: {DniField.votingGroup},
  UbigeoNacimientoExtractor: {DniField.birthUbigeoCode},
};

const _nameToFields = <String, Set<DniField>>{
  'MrzExtractor': {
    DniField.documentNumber,
    DniField.firstName,
    DniField.lastName,
    DniField.secondLastName,
    DniField.dateOfBirth,
    DniField.expirationDate,
    DniField.sex,
    DniField.nationality,
  },
  'DniNumberExtractor': {DniField.documentNumber},
  'SurnameExtractor': {DniField.lastName, DniField.secondLastName},
  'GivenNamesExtractor': {DniField.firstName},
  'DateFieldExtractor': {
    DniField.dateOfBirth,
    DniField.expirationDate,
    DniField.emissionDate,
    DniField.inscriptionDate,
  },
  'SexExtractor': {DniField.sex},
  'NationalityExtractor': {DniField.nationality},
  'AddressExtractor': {DniField.address},
  'UbigeoExtractor': {DniField.department, DniField.province, DniField.district},
  'StateCivilExtractor': {DniField.stateCivil},
  'TarjetaExtractor': {DniField.cardNumber},
  'DonacionExtractor': {DniField.organDonor},
  'GrupoVotacionExtractor': {DniField.votingGroup},
  'UbigeoNacimientoExtractor': {DniField.birthUbigeoCode},
};

/// Returns the subset of [all] extractors that produce any field in [fields].
List<FieldExtractor> filteredExtractors(
  DniFields? fields,
  List<FieldExtractor> all,
) {
  if (fields == null || fields.length == DniField.values.length) {
    return all;
  }
  return all.where((e) {
    final produced = _extractorFields[e.runtimeType];
    if (produced == null) return true;
    return produced.any(fields.contains);
  }).toList();
}

/// Whether the extractor named [extractorClassName] should run for [selectedFields].
bool shouldRunExtractor(String extractorClassName, DniFields? selectedFields) {
  if (selectedFields == null) return true;
  final produced = _nameToFields[extractorClassName];
  if (produced == null) return true;
  return produced.any(selectedFields.contains);
}

/// Scales the fast-advance threshold based on the number of selected fields.
int scaledThreshold(int selectedFieldCount) {
  return (selectedFieldCount * 0.75).round().clamp(3, 14);
}
