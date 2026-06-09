import '../entities/dni_format.dart';
import '../entities/document_side.dart';
import 'extracted_fields.dart';

class HuntResult {
  const HuntResult({
    required this.fields,
    required this.frontDetected,
    required this.backDetected,
    required this.lastSeen,
    this.format = DniFormat.unknown,
  });

  final ExtractedFields fields;
  final bool frontDetected;
  final bool backDetected;
  final DocumentSide lastSeen;
  final DniFormat format;

  DniCompleteness get completeness => DniCompleteness.compute(fields, format);

  bool get isComplete =>
      fields.documentNumber != null &&
      fields.lastName != null &&
      fields.secondLastName != null &&
      fields.firstName != null &&
      fields.dateOfBirth != null &&
      fields.expirationDate != null;
}
