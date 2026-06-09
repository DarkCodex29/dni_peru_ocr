import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../data/ocr_field_extractor.dart';

/// Strategy interface for OCR field extraction.
abstract interface class OcrFieldStrategy {
  /// Attempts to extract OCR fields from [recognized].
  OcrExtractedFields? extract(RecognizedText recognized);
}
