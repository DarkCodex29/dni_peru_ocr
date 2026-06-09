import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';

abstract interface class DniCache {
  Future<DniData?> get(String dni);
  Future<void> set(String dni, DniData data);
  Future<void> evict(String dni);
}
