import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FieldHunter voting', () {
    const frontAnchor = 'DOCUMENTO NACIONAL DE IDENTIDAD\n';

    test('records first occurrence of a field', () {
      final hunter = FieldHunter.standard();
      hunter.process('${frontAnchor}DNI 12345678');
      expect(hunter.snapshot.fields.documentNumber, '12345678');
    });

    test('normalizes diacritic variants and prefers no-diacritic display', () {
      final hunter = FieldHunter.standard();
      hunter.process('${frontAnchor}PRIMER APELLIDO\nMUÑOZ\nPRENOMBRES\nJUAN');
      hunter.process('${frontAnchor}PRIMER APELLIDO\nMUNOZ\nPRENOMBRES\nJUAN');
      hunter.process('${frontAnchor}PRIMER APELLIDO\nMUNHOZ\nPRENOMBRES\nJUAN');
      expect(hunter.snapshot.fields.lastName, 'MUNOZ');
    });

    test('reports added new field when extractor finds something new', () {
      final hunter = FieldHunter.standard();
      final added = hunter.process('${frontAnchor}DNI 12345678');
      expect(added, isTrue);
    });

    test('reports no new field when extractor finds same value again', () {
      final hunter = FieldHunter.standard();
      hunter.process('${frontAnchor}DNI 12345678');
      final added = hunter.process('${frontAnchor}DNI 12345678');
      expect(added, isFalse);
    });

    test('reports added new field when extractor finds a different field', () {
      final hunter = FieldHunter.standard();
      hunter.process('${frontAnchor}DNI 12345678');
      final added = hunter.process('${frontAnchor}PRIMER APELLIDO\nMUÑOZ');
      expect(added, isTrue);
    });

    test('reports no new field when frame produces nothing', () {
      final hunter = FieldHunter.standard();
      hunter.process('${frontAnchor}DNI 12345678');
      final added = hunter.process('${frontAnchor}random text');
      expect(added, isFalse);
    });

    test('preserves voted winner across many frames', () {
      final hunter = FieldHunter.standard();
      for (var i = 0; i < 5; i++) {
        hunter.process('${frontAnchor}DNI 12345678');
      }
      hunter.process('${frontAnchor}DNI 87654321');
      expect(hunter.snapshot.fields.documentNumber, '12345678');
    });
  });
}
