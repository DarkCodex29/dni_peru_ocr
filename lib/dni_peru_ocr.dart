/// Peruvian DNI OCR helpers for Flutter.
///
/// Process Google ML Kit Latin TextRecognizer output against the Peruvian
/// Documento Nacional de Identidad. Recover diacritics, parse MRZ, extract
/// addresses, and merge surnames across OCR + stored profile sources.
library dni_peru_ocr;

export 'src/breadcrumb_throttle.dart';
export 'src/camera_overlay_logic.dart';
export 'src/image_quality_gate.dart';
export 'src/input_image_converter.dart';
export 'src/kyc_image_utils.dart';
export 'src/kyc_theme.dart';
export 'src/ocr_consensus.dart';
export 'src/ocr_field_extractor.dart';
export 'src/ocr_field_normalizer.dart';
export 'src/ocr_logger.dart';
export 'src/string_similarity.dart';
export 'src/tilt_calculator.dart';
