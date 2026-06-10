import 'dart:collection';
import 'dni_field.dart';

/// Immutable set of [DniField] values selecting which fields to extract.
final class DniFields {
  const DniFields._(this._fields);

  factory DniFields.required(Set<DniField> fields) {
    if (fields.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'must not be empty');
    }
    return DniFields._(Set.unmodifiable(fields));
  }

  factory DniFields.minimal() {
    return DniFields._(Set.unmodifiable({
      DniField.documentNumber,
      DniField.firstName,
      DniField.lastName,
      DniField.secondLastName,
    }));
  }

  factory DniFields.kyc() {
    return DniFields._(Set.unmodifiable({
      DniField.documentNumber,
      DniField.firstName,
      DniField.lastName,
      DniField.secondLastName,
      DniField.dateOfBirth,
      DniField.expirationDate,
      DniField.address,
    }));
  }

  factory DniFields.full() {
    return DniFields._(Set.unmodifiable(DniField.values.toSet()));
  }

  final Set<DniField> _fields;

  /// Fields printed on the front side of a Peruvian DNI.
  static const Set<DniField> frontSideFields = {
    DniField.documentNumber,
    DniField.firstName,
    DniField.lastName,
    DniField.secondLastName,
    DniField.dateOfBirth,
    DniField.expirationDate,
    DniField.emissionDate,
    DniField.inscriptionDate,
    DniField.sex,
    DniField.nationality,
    DniField.stateCivil,
    DniField.cardNumber,
  };

  /// Fields printed on the back side of a Peruvian DNI.
  static const Set<DniField> backSideFields = {
    DniField.address,
    DniField.department,
    DniField.province,
    DniField.district,
    DniField.organDonor,
    DniField.votingGroup,
    DniField.birthUbigeoCode,
  };

  Set<DniField> get fields => UnmodifiableSetView(_fields);

  bool contains(DniField field) => _fields.contains(field);

  int get length => _fields.length;

  /// Number of selected fields that live on the front side.
  int get frontCount => _fields.where(frontSideFields.contains).length;

  /// Number of selected fields that live on the back side.
  int get backCount => _fields.where(backSideFields.contains).length;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DniFields) return false;
    if (_fields.length != other._fields.length) return false;
    return _fields.containsAll(other._fields);
  }

  @override
  int get hashCode {
    final sorted = _fields.toList()..sort((a, b) => a.index.compareTo(b.index));
    return Object.hashAll(sorted);
  }

  @override
  String toString() => 'DniFields(${_fields.map((e) => e.name).join(', ')})';
}
