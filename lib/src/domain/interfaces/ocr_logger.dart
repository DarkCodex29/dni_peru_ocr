/// Pluggable logging interface for the OCR pipeline.
abstract class OcrLogger {
  const OcrLogger();

  void breadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  });
}

/// No-op logger that discards all events.
class NoOpOcrLogger implements OcrLogger {
  const NoOpOcrLogger();

  @override
  void breadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) {}
}
