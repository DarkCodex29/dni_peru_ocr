import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('DniScanHints.documentAbsent (#5540)', () {
    test('defaults to neutral Spanish "No se detecta el documento"', () {
      const hints = DniScanHints();
      expect(hints.documentAbsent, 'No se detecta el documento');
    });

    test('is configurable so a published library can localize the warning', () {
      const hints = DniScanHints(documentAbsent: 'No document detected');
      expect(hints.documentAbsent, 'No document detected');
    });

    test('the default warning does not name a specific DNI field', () {
      const hints = DniScanHints();
      final lower = hints.documentAbsent.toLowerCase();
      for (final term in const ['nombres', 'apellidos', 'votación', 'sufragio']) {
        expect(
          lower.contains(term),
          isFalse,
          reason: 'the document-absent copy must guide the action, not a field',
        );
      }
    });
  });
}
