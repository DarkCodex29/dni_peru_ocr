enum DocumentSide { front, back, unknown }

class DocumentSideDetector {
  const DocumentSideDetector();

  static final RegExp _frontPattern = RegExp(
    r'REP[UÚÙÛŨŬ]BLICA\s+DEL\s+PER[UÚÙÛŨŬ]'
    r'|DOCUMENTO\s+NACIONAL\s+DE\s+IDENTIDAD'
    r'|REGISTRO\s+NACIONAL\s+DE\s+IDENTIFICACI[ÓO]N',
  );

  static final RegExp _backPattern = RegExp(
    r'DONACI[ÓO]N\s+DE\s+[ÓO]RGANOS'
    r'|CONSTANCIA\s+DE\s+SUFRAGIO',
  );

  DocumentSide detect(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    if (_backPattern.hasMatch(upper)) return DocumentSide.back;
    if (_frontPattern.hasMatch(upper)) return DocumentSide.front;
    return DocumentSide.unknown;
  }
}
