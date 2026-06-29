import 'package:logger/logger.dart';

/// Process-wide debug logger for the DNI OCR pipeline. Disabled by default.
class DniLogger {
  DniLogger._();

  static bool _enabled = false;
  static bool _verbose = false;
  static Logger? _logger;

  static bool get isEnabled => _enabled;

  /// Whether high-frequency per-frame / per-field logs are emitted. Off by
  /// default so a diagnostic run is not flooded by OCR vote noise.
  static bool get isVerbose => _enabled && _verbose;

  /// Turns the pipeline logging on. Pass `verbose: true` to also emit the
  /// high-frequency per-frame and per-field logs.
  static void enable({bool verbose = false}) {
    _enabled = true;
    _verbose = verbose;
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

  /// Turns the pipeline logging off.
  static void disable() {
    _enabled = false;
    _verbose = false;
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

  /// High-frequency per-frame / per-field log. Suppressed unless logging was
  /// enabled with `verbose: true`, keeping diagnostic runs readable.
  static void verbose(String tag, String message) {
    if (!_enabled || !_verbose) return;
    _emit('VERBOSE', tag, message);
    _logger?.t('[$tag] $message');
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

  static void _emit(String level, String tag, String message) {
    // ignore: avoid_print
    print('DNI_OCR[$level][$tag] $message');
  }
}
