import '../extraction/extracted_fields.dart';

enum DniFormat { unknown, azulBooklet, modelo2020 }

class DniFormatDetector {
  const DniFormatDetector();

  static final RegExp _azulSignals = RegExp(
    r'PRIMER\s+APELLIDO|SEGUNDO\s+APELLIDO'
    r'|PRE\s+NOMBRES|NACIMIENTO\s*:\s*FECHA\s+Y\s+UBIGEO',
  );
  static final RegExp _modelo2020Signals = RegExp(
    r'\bCUI\b|^APELLIDOS\s*$|NRO[\.\s]+DE\s+TARJETA'
    r'|FECHA\s+DE\s+CADUCIDAD|FECHA\s+DE\s+EMISI[ÓO]N',
    multiLine: true,
  );

  DniFormat detect(String recognizedText) {
    final upper = recognizedText.toUpperCase();
    final azul = _azulSignals.hasMatch(upper);
    final modelo = _modelo2020Signals.hasMatch(upper);
    if (modelo && !azul) return DniFormat.modelo2020;
    if (azul && !modelo) return DniFormat.azulBooklet;
    return DniFormat.unknown;
  }
}

extension DniFormatFields on DniFormat {
  Set<String> get expectedFields {
    switch (this) {
      case DniFormat.azulBooklet:
        return const {
          'documentNumber',
          'firstName',
          'lastName',
          'secondLastName',
          'dateOfBirth',
          'expirationDate',
          'emissionDate',
          'inscriptionDate',
          'sex',
          'nationality',
          'stateCivil',
          'address',
          'department',
          'province',
          'district',
          'organDonor',
          'votingGroup',
          'birthUbigeoCode',
        };
      case DniFormat.modelo2020:
        return const {
          'documentNumber',
          'firstName',
          'lastName',
          'secondLastName',
          'dateOfBirth',
          'expirationDate',
          'emissionDate',
          'sex',
          'nationality',
          'stateCivil',
          'cardNumber',
          'address',
          'department',
          'province',
          'district',
          'organDonor',
          'votingGroup',
          'birthUbigeoCode',
        };
      case DniFormat.unknown:
        return const {
          'documentNumber',
          'firstName',
          'lastName',
          'secondLastName',
          'dateOfBirth',
          'expirationDate',
          'emissionDate',
          'inscriptionDate',
          'sex',
          'nationality',
          'stateCivil',
          'cardNumber',
          'address',
          'department',
          'province',
          'district',
          'organDonor',
          'votingGroup',
          'birthUbigeoCode',
        };
    }
  }

  bool fieldApplies(String name) => expectedFields.contains(name);
}

class DniCompleteness {
  const DniCompleteness({
    required this.detected,
    required this.expected,
    required this.missing,
    required this.notApplicable,
  });

  final int detected;
  final int expected;
  final List<String> missing;
  final List<String> notApplicable;

  double get ratio => expected == 0 ? 0 : detected / expected;

  static DniCompleteness compute(ExtractedFields f, DniFormat format) {
    final values = <String, String?>{
      'documentNumber': f.documentNumber,
      'firstName': f.firstName,
      'lastName': f.lastName,
      'secondLastName': f.secondLastName,
      'dateOfBirth': f.dateOfBirth,
      'expirationDate': f.expirationDate,
      'emissionDate': f.emissionDate,
      'inscriptionDate': f.inscriptionDate,
      'sex': f.sex,
      'nationality': f.nationality,
      'address': f.address,
      'department': f.department,
      'province': f.province,
      'district': f.district,
      'stateCivil': f.stateCivil,
      'cardNumber': f.cardNumber,
      'organDonor': f.organDonor,
      'votingGroup': f.votingGroup,
      'birthUbigeoCode': f.birthUbigeoCode,
    };
    final expectedSet = format.expectedFields;
    final missing = <String>[];
    final notApplicable = <String>[];
    var detected = 0;
    for (final entry in values.entries) {
      final inExpected = expectedSet.contains(entry.key);
      if (!inExpected) {
        if (entry.value == null) notApplicable.add(entry.key);
        continue;
      }
      if (entry.value != null) {
        detected++;
      } else {
        missing.add(entry.key);
      }
    }
    return DniCompleteness(
      detected: detected,
      expected: expectedSet.length,
      missing: missing,
      notApplicable: notApplicable,
    );
  }
}
