import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';

abstract interface class DniLookupService {
  Future<DniLookupResult> lookup(String dni);
}
