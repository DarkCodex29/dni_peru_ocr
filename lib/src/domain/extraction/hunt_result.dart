import '../entities/dni_format.dart';
import '../entities/document_side.dart';
import 'dni_field.dart';
import 'dni_fields.dart';
import 'extracted_fields.dart';

class HuntResult {
  const HuntResult({
    required this.fields,
    required this.frontDetected,
    required this.backDetected,
    required this.lastSeen,
    this.format = DniFormat.unknown,
    this.requiredFields,
  });

  final ExtractedFields fields;
  final bool frontDetected;
  final bool backDetected;
  final DocumentSide lastSeen;
  final DniFormat format;

  final DniFields? requiredFields;

  /// Fields physically printed on the front side of the DNI.
  static const Set<DniField> frontPrintedFields = {
    DniField.documentNumber,
    DniField.firstName,
    DniField.lastName,
    DniField.secondLastName,
    DniField.sex,
    DniField.nationality,
    DniField.organDonor,
    DniField.votingGroup,
    DniField.stateCivil,
  };

  DniCompleteness get completeness => DniCompleteness.compute(fields, format);

  bool get isComplete {
    final selection = requiredFields;
    if (selection == null) {
      return fields.documentNumber != null &&
          fields.lastName != null &&
          fields.secondLastName != null &&
          fields.firstName != null &&
          fields.dateOfBirth != null &&
          fields.expirationDate != null;
    }
    for (final field in selection.fields) {
      if (!_hasValue(fields, field)) return false;
    }
    return true;
  }

  /// True when every requested front-printed field has been extracted.
  bool get isFrontReady {
    final selection = requiredFields;
    if (selection == null) {
      return fields.documentNumber != null &&
          fields.lastName != null &&
          fields.firstName != null;
    }
    final requested = selection.fields.intersection(frontPrintedFields);
    if (requested.isEmpty) {
      return fields.documentNumber != null;
    }
    for (final field in requested) {
      if (!_hasValue(fields, field)) return false;
    }
    return true;
  }

  static bool _hasValue(ExtractedFields f, DniField field) {
    switch (field) {
      case DniField.documentNumber:
        return f.documentNumber != null;
      case DniField.firstName:
        return f.firstName != null;
      case DniField.lastName:
        return f.lastName != null;
      case DniField.secondLastName:
        return f.secondLastName != null;
      case DniField.dateOfBirth:
        return f.dateOfBirth != null;
      case DniField.expirationDate:
        return f.expirationDate != null;
      case DniField.emissionDate:
        return f.emissionDate != null;
      case DniField.inscriptionDate:
        return f.inscriptionDate != null;
      case DniField.sex:
        return f.sex != null;
      case DniField.nationality:
        return f.nationality != null;
      case DniField.address:
        return f.address != null;
      case DniField.department:
        return f.department != null;
      case DniField.province:
        return f.province != null;
      case DniField.district:
        return f.district != null;
      case DniField.stateCivil:
        return f.stateCivil != null;
      case DniField.cardNumber:
        return f.cardNumber != null;
      case DniField.organDonor:
        return f.organDonor != null;
      case DniField.votingGroup:
        return f.votingGroup != null;
      case DniField.birthUbigeoCode:
        return f.birthUbigeoCode != null;
    }
  }
}
