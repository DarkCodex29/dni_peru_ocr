/// Pluggable logging interface for the OCR pipeline.
///
/// The package emits breadcrumb-style events on key decisions
/// (denoise applied, label rejected, MRZ vs text-OCR mismatch, etc.)
/// so the host application can route them to its observability platform
/// (Sentry, Crashlytics, Datadog, console, etc.).
///
/// Use [NoOpOcrLogger] when you do not need observability.
abstract class OcrLogger {
  const OcrLogger();

  /// Records a breadcrumb-style event.
  ///
  /// - [category]: namespace, e.g. `"kyc-ocr-denoise"`, `"kyc-ocr-mrz"`.
  /// - [message]: short human-readable description.
  /// - [data]: optional structured payload.
  void breadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  });
}

/// Default no-op logger. Discards all events.
class NoOpOcrLogger implements OcrLogger {
  const NoOpOcrLogger();

  @override
  void breadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) {}
}
