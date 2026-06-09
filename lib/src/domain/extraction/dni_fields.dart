import 'dart:collection';
import 'dni_field.dart';

/// Immutable wrapper around a set of [DniField] values that controls which
/// fields the DNI pipeline MUST extract and merge.
final class DniFields {
  const DniFields._(this._fields);

  /// Returns a [DniFields] containing exactly [fields].
  ///
  /// Throws [ArgumentError] if [fields] is empty.
  factory DniFields.required(Set<DniField> fields) {
    if (fields.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'must not be empty');
    }
    return DniFields._(Set.unmodifiable(fields));
  }

  /// Returns a [DniFields] with the 4 identity fields:
  /// documentNumber, firstName, lastName, secondLastName.
  factory DniFields.minimal() {
    return DniFields._(Set.unmodifiable({
      DniField.documentNumber,
      DniField.firstName,
      DniField.lastName,
      DniField.secondLastName,
    }));
  }

  /// Returns a [DniFields] with the 7 KYC fields:
  /// documentNumber, firstName, lastName, secondLastName,
  /// dateOfBirth, expirationDate, address.
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

  /// Returns a [DniFields] containing all 19 [DniField] values.
  factory DniFields.full() {
    return DniFields._(Set.unmodifiable(DniField.values.toSet()));
  }

  final Set<DniField> _fields;

  /// Unmodifiable view of the selected fields.
  Set<DniField> get fields => UnmodifiableSetView(_fields);

  /// Whether [field] is included in the selection.
  bool contains(DniField field) => _fields.contains(field);

  /// Number of selected fields.
  int get length => _fields.length;

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
