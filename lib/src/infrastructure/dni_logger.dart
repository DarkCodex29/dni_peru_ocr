import 'package:logger/logger.dart';

/// Process-wide debug logger for the DNI OCR pipeline.
///
/// OFF by default. Host apps enable it from `main()` for diagnostics —
/// every frame, partial extraction, vote, and snapshot is then emitted to
/// both `print` (release-build logcat) and the `logger` package (pretty
/// formatting in debug). Production apps should keep it disabled to avoid
/// leaking document text.
class DniLogger {
  DniLogger._();

  static bool _enabled = false;
  static Logger? _logger;

  static bool get isEnabled => _enabled;

  /// Turn the pipeline logging ON. Safe to call multiple times.
  static void enable() {
    _enabled = true;
    _logger ??= Logger(
      printer: PrettyPrinter(
        methodCount: 0,
        errorMethodCount: 5,
        lineLength: 100,
        colors: false,
        printEmojis: true,
        dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
      ),
    );
  }

  /// Turn the pipeline logging OFF.
  static void disable() {
    _enabled = false;
  }

  static void info(String tag, String message) {
    if (!_enabled) return;
    _emit('INFO', tag, message);
    _logger?.i('[$tag] $message');
  }

  static void debug(String tag, String message) {
    if (!_enabled) return;
    _emit('DEBUG', tag, message);
    _logger?.d('[$tag] $message');
  }

  static void warn(String tag, String message) {
    if (!_enabled) return;
    _emit('WARN', tag, message);
    _logger?.w('[$tag] $message');
  }

  static void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    if (!_enabled) return;
    _emit('ERROR', tag, message);
    _logger?.e('[$tag] $message', error: error, stackTrace: stackTrace);
  }

  /// Emits to plain `print` so it reaches release-build logcat
  /// (where `logger` is not visible).
  static void _emit(String level, String tag, String message) {
    // ignore: avoid_print
    print('DNI_OCR[$level][$tag] $message');
  }
}
