class UserVerificationData {
  const UserVerificationData({
    required this.name,
    required this.lastName,
    required this.documentNumber,
  });

  final String name;
  final String lastName;
  final String documentNumber;

  /// Checks whether the OCR text contains this document number.
  bool matchesText(String fullText) {
    if (documentNumber.isEmpty) return true;

    final cleanDoc = documentNumber.replaceAll(RegExp('[^0-9]'), '');
    if (cleanDoc.isEmpty) return true;

    final cleanOcr = fullText.replaceAll(RegExp('[^0-9A-Za-z<]'), '');

    if (cleanOcr.contains(cleanDoc)) return true;

    if (cleanDoc.length >= 6) {
      for (int i = 0; i <= cleanDoc.length - 6; i++) {
        if (cleanOcr.contains(cleanDoc.substring(i, i + 6))) return true;
      }
    }

    return false;
  }
}
