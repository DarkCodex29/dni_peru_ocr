import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/ocr_field_extractor.dart';

/// Strategy interface for OCR field extraction.
///
/// Each implementation is responsible for extracting a specific subset of
/// fields from a [RecognizedText]. Strategies are stateless: they take inputs
/// and return outputs without modifying shared state.
abstract interface class OcrFieldStrategy {
  /// Attempts to extract OCR fields from [recognized].
  ///
  /// Returns `null` when the strategy cannot find enough signal in [recognized]
  /// (e.g., no MRZ block found). Returns a partially or fully populated
  /// [OcrExtractedFields] when at least some fields were found.
  OcrExtractedFields? extract(RecognizedText recognized);
}
