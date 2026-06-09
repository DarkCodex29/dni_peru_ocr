import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/domain/extraction/dni_field.dart';
import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';

void main() {
  group('DniFields.required', () {
    test('single-field set returns DniFields with length 1', () {
      final f = DniFields.required({DniField.documentNumber});
      expect(f.length, 1);
      expect(f.contains(DniField.documentNumber), isTrue);
    });

    test('multi-field set returns correct length', () {
      final f = DniFields.required({DniField.firstName, DniField.lastName});
      expect(f.length, 2);
    });

    test('empty set throws ArgumentError', () {
      expect(() => DniFields.required({}), throwsArgumentError);
    });
  });

  group('DniFields.minimal', () {
    test('length is 4', () {
      expect(DniFields.minimal().length, 4);
    });

    test('contains documentNumber, firstName, lastName, secondLastName', () {
      final f = DniFields.minimal();
      expect(f.contains(DniField.documentNumber), isTrue);
      expect(f.contains(DniField.firstName), isTrue);
      expect(f.contains(DniField.lastName), isTrue);
      expect(f.contains(DniField.secondLastName), isTrue);
    });

    test('does not contain address', () {
      expect(DniFields.minimal().contains(DniField.address), isFalse);
    });

    test('does not contain sex', () {
      expect(DniFields.minimal().contains(DniField.sex), isFalse);
    });
  });

  group('DniFields.kyc', () {
    test('length is 7', () {
      expect(DniFields.kyc().length, 7);
    });

    test('contains the 7 KYC fields', () {
      final f = DniFields.kyc();
      expect(f.contains(DniField.documentNumber), isTrue);
      expect(f.contains(DniField.firstName), isTrue);
      expect(f.contains(DniField.lastName), isTrue);
      expect(f.contains(DniField.secondLastName), isTrue);
      expect(f.contains(DniField.dateOfBirth), isTrue);
      expect(f.contains(DniField.expirationDate), isTrue);
      expect(f.contains(DniField.address), isTrue);
    });

    test('does not contain organDonor', () {
      expect(DniFields.kyc().contains(DniField.organDonor), isFalse);
    });

    test('does not contain department', () {
      expect(DniFields.kyc().contains(DniField.department), isFalse);
    });
  });

  group('DniFields.full', () {
    test('length is 19', () {
      expect(DniFields.full().length, 19);
    });

    test('contains all DniField values', () {
      final f = DniFields.full();
      for (final field in DniField.values) {
        expect(f.contains(field), isTrue, reason: 'missing $field');
      }
    });

    test('equals DniFields.required with all values', () {
      expect(DniFields.full(), equals(DniFields.required(DniField.values.toSet())));
    });

    test('length matches DniField.values.length', () {
      expect(DniFields.full().length, DniField.values.length);
    });
  });

  group('DniFields equality and hashCode', () {
    test('two independent kyc() calls are equal', () {
      expect(DniFields.kyc(), equals(DniFields.kyc()));
    });

    test('two equal instances have same hashCode', () {
      expect(DniFields.kyc().hashCode, equals(DniFields.kyc().hashCode));
    });

    test('minimal() and kyc() are not equal', () {
      expect(DniFields.minimal(), isNot(equals(DniFields.kyc())));
    });
  });

  group('DniFields.fields getter', () {
    test('returns correct elements for minimal', () {
      final f = DniFields.minimal();
      expect(f.fields.length, 4);
      expect(f.fields.contains(DniField.documentNumber), isTrue);
    });

    test('returns unmodifiable set — add throws UnsupportedError', () {
      final f = DniFields.minimal();
      expect(() => f.fields.add(DniField.sex), throwsUnsupportedError);
    });
  });

  group('DniFields.toString', () {
    test('returns a non-empty string', () {
      expect(DniFields.minimal().toString(), isNotEmpty);
    });

    test('contains class name', () {
      expect(DniFields.minimal().toString(), contains('DniFields'));
    });
  });
}
