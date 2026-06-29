/// User-facing rotating guidance shown along the bottom of [DniScanner].
///
/// Each list holds the rotating hints for one scanning phase. The copy is
/// intentionally GENERIC: it guides the physical action (focus, hold still,
/// flip) and never names a specific DNI field. The side a field belongs to is
/// not knowable across the many Peru DNI versions, and a confidently captured
/// field is locked, so requesting a field by name is always an invalid
/// assumption (#5486).
///
/// All lists are configurable so a published-library consumer can localize or
/// reword the guidance. Defaults are neutral Spanish.
class DniScanHints {
  const DniScanHints({
    this.waitingFront = _defaultWaitingFront,
    this.extractingFront = _defaultExtractingFront,
    this.waitingBack = _defaultWaitingBack,
    this.extractingBack = _defaultExtractingBack,
    this.processing = _defaultProcessing,
    this.documentAbsent = _defaultDocumentAbsent,
  });

  /// Hints while waiting to detect the front side.
  final List<String> waitingFront;

  /// Hints while actively extracting from the front side.
  final List<String> extractingFront;

  /// Hints while waiting for the user to flip to the back side.
  final List<String> waitingBack;

  /// Hints while actively extracting from the back side.
  final List<String> extractingBack;

  /// Hint shown once both sides are captured and processing.
  final String processing;

  /// Top-banner warning shown when no document is detected in the frame while
  /// scanning a side — e.g. the user removed the DNI mid-countdown, which
  /// cancels the auto-capture (#5540). Configurable so a published-library
  /// consumer can localize or reword it. Default is neutral Spanish.
  final String documentAbsent;

  static const List<String> _defaultWaitingFront = [
    'Coloca el documento dentro del marco',
    'Enfoca el documento',
    'Usa buena iluminación y evita reflejos',
  ];

  static const List<String> _defaultExtractingFront = [
    'Mantén el documento quieto',
    'Acerca un poco el documento si no enfoca',
    'Sostén firme unos segundos',
  ];

  static const List<String> _defaultWaitingBack = [
    'Voltea el documento',
    'Coloca el documento dentro del marco',
    'Enfoca el documento',
  ];

  static const List<String> _defaultExtractingBack = [
    'Mantén el documento quieto',
    'Sostén firme unos segundos',
    'Acerca un poco el documento si no enfoca',
  ];

  static const String _defaultProcessing = 'Procesando…';

  static const String _defaultDocumentAbsent = 'No se detecta el documento';
}
