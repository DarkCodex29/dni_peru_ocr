class UserVerificationData {
  const UserVerificationData({
    required this.name,
    required this.lastName,
    required this.documentNumber,
  });

  final String name;
  final String lastName;
  final String documentNumber;

  /// Compara el número de documento contra el texto OCR.
  ///
  /// Limpia espacios, guiones y caracteres especiales antes de comparar.
  /// Busca el número completo o al menos 6 dígitos consecutivos que coincidan.
  bool matchesText(String fullText) {
    if (documentNumber.isEmpty) return true;

    final cleanDoc = documentNumber.replaceAll(RegExp('[^0-9]'), '');
    if (cleanDoc.isEmpty) return true;

    final cleanOcr = fullText.replaceAll(RegExp('[^0-9A-Za-z<]'), '');

    // Match exacto (sin espacios/guiones)
    if (cleanOcr.contains(cleanDoc)) return true;

    // Match parcial: al menos 6 dígitos consecutivos del documento
    if (cleanDoc.length >= 6) {
      for (int i = 0; i <= cleanDoc.length - 6; i++) {
        if (cleanOcr.contains(cleanDoc.substring(i, i + 6))) return true;
      }
    }

    return false;
  }
}
