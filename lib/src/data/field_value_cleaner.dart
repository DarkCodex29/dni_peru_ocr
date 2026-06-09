import 'address_noise_filter.dart';

class FieldValueCleaner {
  const FieldValueCleaner();

  String? clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final tokens = trimmed.split(RegExp(r'\s+'));
    final kept = <String>[];
    for (final token in tokens) {
      final key = _denylistKey(token);
      if (key.isEmpty) continue;
      if (AddressNoiseFilter.kAddressNoiseDenylist.contains(key)) continue;
      kept.add(token);
    }
    if (kept.isEmpty) return null;
    return kept.join(' ');
  }

  String _denylistKey(String token) {
    return token
        .toUpperCase()
        .replaceAll(RegExp(r'[ÁÀÄÂÃ]'), 'A')
        .replaceAll(RegExp(r'[ÉÈËÊ]'), 'E')
        .replaceAll(RegExp(r'[ÍÌÏÎ]'), 'I')
        .replaceAll(RegExp(r'[ÓÒÖÔÕ]'), 'O')
        .replaceAll(RegExp(r'[ÚÙÜÛ]'), 'U')
        .replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }
}
