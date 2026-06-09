import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GrupoVotacionExtractor', () {
    const extractor = GrupoVotacionExtractor();

    test('extracts 6-digit voting group after label', () {
      expect(
        extractor.extract('GRUPO DE VOTACIÓN\n123456').votingGroup,
        '123456',
      );
    });

    test('handles abbreviated GRUPO VOTACION', () {
      expect(
        extractor.extract('GRUPO VOTACION\n987654').votingGroup,
        '987654',
      );
    });

    test('handles colon on same line', () {
      expect(
        extractor.extract('GRUPO DE VOTACIÓN: 045678').votingGroup,
        '045678',
      );
    });

    test('keeps leading zeros', () {
      expect(
        extractor.extract('GRUPO DE VOTACIÓN\n002345').votingGroup,
        '002345',
      );
    });

    test('handles GV abbreviated label', () {
      expect(extractor.extract('GV\n123456').votingGroup, '123456');
    });

    test('returns null when no label present', () {
      expect(extractor.extract('hola 123456 mundo').votingGroup, isNull);
    });

    test('returns null when value is not exactly 6 digits', () {
      expect(
        extractor.extract('GRUPO DE VOTACIÓN\n12345').votingGroup,
        isNull,
      );
      expect(
        extractor.extract('GRUPO DE VOTACIÓN\n1234567').votingGroup,
        isNull,
      );
    });

    test('finds value within 2 lines after label', () {
      expect(
        extractor.extract('GRUPO DE VOTACIÓN\n\n654321').votingGroup,
        '654321',
      );
    });
  });
}
