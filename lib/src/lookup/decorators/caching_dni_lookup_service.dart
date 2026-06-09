import 'package:dni_peru_ocr/src/lookup/cache/dni_cache.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

/// Decorator that adds in-memory TTL-gated caching to any [DniLookupService].
///
/// Only [DniLookupSuccess] results are cached. Non-success variants are returned
/// as-is and never stored. TTL is tracked per-instance, not globally.
final class CachingDniLookupService implements DniLookupService {
  CachingDniLookupService({
    required this.delegate,
    required this.cache,
    this.ttl,
  });

  final DniLookupService delegate;
  final DniCache cache;
  final Duration? ttl;

  final Map<String, DateTime> _writtenAt = {};

  @override
  Future<DniLookupResult> lookup(String dni) async {
    final cached = await cache.get(dni);

    if (cached != null) {
      if (ttl == null) {
        return DniLookupSuccess(cached);
      }
      final written = _writtenAt[dni];
      if (written != null && DateTime.now().difference(written) <= ttl!) {
        return DniLookupSuccess(cached);
      }
      await cache.evict(dni);
      _writtenAt.remove(dni);
    }

    final result = await delegate.lookup(dni);

    if (result is DniLookupSuccess) {
      await cache.set(dni, result.data);
      _writtenAt[dni] = DateTime.now();
    }

    return result;
  }
}
