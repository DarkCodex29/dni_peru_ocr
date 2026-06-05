/// Peruvian DNI OCR helpers for Flutter.
///
/// Process Google ML Kit Latin TextRecognizer output against the Peruvian
/// Documento Nacional de Identidad. Recover diacritics, parse MRZ, extract
/// addresses, and merge surnames across OCR + stored profile sources.
library dni_peru_ocr;

export 'src/data/address_noise_filter.dart';
export 'src/data/ocr_consensus.dart';
export 'src/data/ocr_field_extractor.dart';
export 'src/data/ocr_field_normalizer.dart';
export 'src/data/string_similarity.dart';
export 'src/data/strategies/address_field_strategy.dart';
export 'src/data/strategies/mrz_field_strategy.dart';
export 'src/data/strategies/ocr_field_strategy.dart';
export 'src/data/strategies/text_ocr_field_strategy.dart';
export 'src/domain/entities/user_verification_data.dart';
export 'src/domain/entities/validation_gate.dart';
export 'src/domain/interfaces/ocr_logger.dart';
export 'src/infrastructure/breadcrumb_throttle.dart';
export 'src/infrastructure/detector_lifecycle.dart';
export 'src/infrastructure/input_image_converter.dart';
export 'src/infrastructure/kyc_image_utils.dart';
export 'src/infrastructure/tilt_calculator.dart';
export 'src/presentation/camera_overlay_logic.dart';
export 'src/presentation/document_validator.dart';
export 'src/presentation/validation_gate_colors.dart';
export 'src/presentation/image_quality_gate.dart';
export 'src/presentation/controllers/dni_camera_controller.dart';
export 'src/presentation/orchestrators/dni_capture_orchestrator.dart';
export 'src/presentation/orchestrators/dni_capture_state.dart';
export 'src/presentation/theme/kyc_theme.dart';
export 'src/presentation/widgets/dni_camera_mask.dart';
