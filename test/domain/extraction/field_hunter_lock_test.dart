import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FieldHunter data lock (#5486)', () {
    const frontAnchor = 'DOCUMENTO NACIONAL DE IDENTIDAD\n';

    test(
        'once a field reaches the lock threshold its winner is FIXED and a '
        'later value with MORE votes does not overturn it', () {
      final hunter = FieldHunter.standard();

      // Drive the document number past the lock threshold with one value.
      for (var i = 0; i < FieldHunter.lockVoteThreshold; i++) {
        hunter.process('${frontAnchor}DNI 12345678');
      }
      expect(
        hunter.snapshot.fields.documentNumber,
        '12345678',
        reason: 'the repeatedly-read value should win before any challenger',
      );

      // A different value now accumulates strictly MORE votes than the locked
      // winner. Without a lock, vote-count dominance would overturn it.
      for (var i = 0; i < FieldHunter.lockVoteThreshold + 5; i++) {
        hunter.process('${frontAnchor}DNI 87654321');
      }

      expect(
        hunter.snapshot.fields.documentNumber,
        '12345678',
        reason: 'a confidently captured field is locked and must never be '
            'overturned by later contradicting reads',
      );
    });

    test(
        'a locked field is not re-processed: a frame carrying only a '
        'contradicting value for it reports no new field', () {
      final hunter = FieldHunter.standard();

      for (var i = 0; i < FieldHunter.lockVoteThreshold; i++) {
        hunter.process('${frontAnchor}DNI 12345678');
      }

      // The field is locked; a contradicting read for ONLY that field must not
      // register as new data (no re-vote, no re-processing).
      final added = hunter.process('${frontAnchor}DNI 87654321');

      expect(
        added,
        isFalse,
        reason: 'a locked field must not accept new votes — it is fixed',
      );
    });

    test('isLocked reports false below threshold and true once reached', () {
      final hunter = FieldHunter.standard();

      hunter.process('${frontAnchor}DNI 12345678');
      expect(
        hunter.isLocked(DniField.documentNumber),
        isFalse,
        reason: 'a single vote is not enough confidence to lock',
      );

      for (var i = 1; i < FieldHunter.lockVoteThreshold; i++) {
        hunter.process('${frontAnchor}DNI 12345678');
      }
      expect(
        hunter.isLocked(DniField.documentNumber),
        isTrue,
        reason: 'reaching the vote threshold locks the field',
      );
    });

    test('an unlocked field still updates its winner normally', () {
      final hunter = FieldHunter.standard();

      // Two reads of one value, three of another, neither reaching the lock
      // threshold: the higher-vote value wins and the field is NOT locked.
      hunter.process('${frontAnchor}DNI 12345678');
      expect(hunter.isLocked(DniField.documentNumber), isFalse);
      expect(hunter.snapshot.fields.documentNumber, '12345678');
    });
  });
}
