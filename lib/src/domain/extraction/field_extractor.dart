import 'extracted_fields.dart';

abstract class FieldExtractor {
  const FieldExtractor();

  ExtractedFields extract(String recognizedText);
}
