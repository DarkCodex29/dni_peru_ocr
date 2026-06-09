import 'package:mrz_parser/mrz_parser.dart';

import 'ocr_field_normalizer.dart';
import 'string_similarity.dart';

/// Result for a single OCR field after consensus.
class OcrFieldResult<T> {
  const OcrFieldResult({
    required this.value,
    required this.confidence,
    required this.locked,
  });

  final T? value;
  final double confidence;
  final bool locked;
}

/// Source that triggered the consensus lock.
enum OcrConsensusSource {
  mrzChecksum,
  temporalVote,
  manualFallback,
}

/// Complete consensus snapshot emitted by [OcrConsensusAccumulator].
class OcrConsensusResult {
  const OcrConsensusResult({
    required this.success,
    required this.source,
    required this.documentNumber,
    required this.firstName,
    required this.lastName,
    required this.secondLastName,
    required this.dateOfBirth,
    required this.expirationDate,
    required this.address,
  });

  final bool success;
  final OcrConsensusSource source;

  final OcrFieldResult<String> documentNumber;
  final OcrFieldResult<String> firstName;
  final OcrFieldResult<String> lastName;
  final OcrFieldResult<String> secondLastName;
  final OcrFieldResult<String> dateOfBirth;
  final OcrFieldResult<String> expirationDate;
  final OcrFieldResult<String> address;
}

const _kDocumentNumberThreshold = 0.95;
const _kNameThreshold = 0.80;
const _kAddressThreshold = 0.60;

const _kDateMatchRequired = 4;
const _kDateWindowSize = 5;

const _kMrzConsecutiveRequired = 2;

/// Accumulates per-field OCR consensus across multiple camera frames.
class OcrConsensusAccumulator {
  OcrConsensusAccumulator({
    this.mrzConsecutiveRequired = _kMrzConsecutiveRequired,
  }) : assert(
          mrzConsecutiveRequired >= 1,
          'mrzConsecutiveRequired must be >= 1',
        );

  final int mrzConsecutiveRequired;

  final Map<String, Map<String, int>> _votes = {
    'documentNumber': {},
    'firstName': {},
    'lastName': {},
    'secondLastName': {},
    'address': {},
  };

  final Map<String, Map<String, String>> _displayValues = {
    'documentNumber': {},
    'firstName': {},
    'lastName': {},
    'secondLastName': {},
    'address': {},
  };

  final Map<String, List<String?>> _dateWindows = {
    'dateOfBirth': [],
    'expirationDate': [],
  };

  int _consecutiveMrzCount = 0;

  bool _mrzLocked = false;
  MRZResult? _lockedMrz;

  /// Records OCR field votes for one processed frame.
  void recordVote(Map<String, String?> fields) {
    for (final entry in fields.entries) {
      final rawValue = entry.value;
      if (rawValue == null || rawValue.isEmpty) continue;

      final field = entry.key;

      if (_dateWindows.containsKey(field)) {
        _recordDateVote(field, rawValue);
      } else if (_votes.containsKey(field)) {
        final voteKey = _normalize(field, rawValue);
        _votes[field]![voteKey] = (_votes[field]![voteKey] ?? 0) + 1;
        _updateDisplayValue(field, voteKey, rawValue);
      }
    }
  }

  void _updateDisplayValue(String field, String voteKey, String rawValue) {
    final displayValue = _computeDisplay(field, rawValue);
    final bucket = _displayValues[field]!;
    final current = bucket[voteKey];
    if (current == null) {
      bucket[voteKey] = displayValue;
      return;
    }
    final newHasTilde =
        displayValue.contains('Ñ') || displayValue.contains('ñ');
    final currentHasTilde = current.contains('Ñ') || current.contains('ñ');
    if (newHasTilde && !currentHasTilde) {
      bucket[voteKey] = displayValue;
    }
  }

  String _computeDisplay(String field, String rawValue) {
    switch (field) {
      case 'firstName':
      case 'lastName':
      case 'secondLastName':
        return OcrFieldNormalizer.normalizeForDisplay(rawValue);
      case 'documentNumber':
        return OcrFieldNormalizer.normalizeDocument(rawValue);
      default:
        return rawValue.trim();
    }
  }

  /// Records a checksum-valid MRZ parse.
  void recordMrz(MRZResult mrz) {
    if (_mrzLocked) return;
    _consecutiveMrzCount++;

    if (_consecutiveMrzCount >= mrzConsecutiveRequired) {
      _mrzLocked = true;
      _lockedMrz = mrz;
    }
  }

  /// Fast-locks consensus from MRZ-extracted fields.
  void lockFromMrzFields({
    required String? documentNumber,
    required String? firstName,
    required String? lastName,
    required String? secondLastName,
    required String? dateOfBirth,
    required String? expirationDate,
  }) {
    if (_mrzLocked) return;
    _consecutiveMrzCount++;
    final prev = _mrzFieldsBuffer;
    _mrzFieldsBuffer = _MrzFieldsBuffer(
      documentNumber: documentNumber ?? prev?.documentNumber,
      firstName: firstName ?? prev?.firstName,
      lastName: lastName ?? prev?.lastName,
      secondLastName: secondLastName ?? prev?.secondLastName,
      dateOfBirth: dateOfBirth ?? prev?.dateOfBirth,
      expirationDate: expirationDate ?? prev?.expirationDate,
    );
    if (_consecutiveMrzCount >= mrzConsecutiveRequired) {
      _mrzLocked = true;
    }
  }

  /// Resets the MRZ consecutive counter without clearing the buffer.
  void resetMrzConsecutiveCount() {
    if (_mrzLocked) return;
    _consecutiveMrzCount = 0;
  }

  _MrzFieldsBuffer? _mrzFieldsBuffer;

  bool get isMrzLocked => _mrzLocked;

  bool checkAllThresholds() {
    if (_mrzLocked) return true;

    return _isDocumentNumberLocked() &&
        _isNameLocked('firstName') &&
        _isNameLocked('lastName') &&
        _isDateLocked('dateOfBirth') &&
        _isDateLocked('expirationDate');
  }

  /// Emits the current [OcrConsensusResult].
  OcrConsensusResult snapshot() {
    if (_mrzLocked && _lockedMrz != null) {
      return _buildMrzResult(_lockedMrz!);
    }
    if (_mrzFieldsBuffer != null) {
      return _buildMrzResultFromFields(_mrzFieldsBuffer!);
    }

    final isFullyLocked = checkAllThresholds();
    return OcrConsensusResult(
      success: isFullyLocked,
      source: isFullyLocked
          ? OcrConsensusSource.temporalVote
          : OcrConsensusSource.manualFallback,
      documentNumber: _voteResult('documentNumber', _kDocumentNumberThreshold),
      firstName: _voteResult('firstName', _kNameThreshold),
      lastName: _voteResult('lastName', _kNameThreshold),
      secondLastName: _voteResult('secondLastName', _kNameThreshold),
      dateOfBirth: _dateResult('dateOfBirth'),
      expirationDate: _dateResult('expirationDate'),
      address: _voteResult('address', _kAddressThreshold),
    );
  }

  void dispose() {}

  String _normalize(String field, String value) {
    switch (field) {
      case 'firstName':
      case 'lastName':
      case 'secondLastName':
        return OcrFieldNormalizer.normalizeName(value);
      case 'documentNumber':
        return OcrFieldNormalizer.normalizeDocument(value);
      default:
        return value.trim();
    }
  }

  void _recordDateVote(String field, String rawValue) {
    final window = _dateWindows[field]!..add(rawValue.trim());
    if (window.length > _kDateWindowSize) window.removeAt(0);
  }

  bool _isDocumentNumberLocked() {
    final map = _votes['documentNumber']!;
    if (map.isEmpty) return false;
    final total = map.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return false;
    final maxCount = map.values.reduce((a, b) => a > b ? a : b);
    return maxCount / total >= _kDocumentNumberThreshold;
  }

  bool _isNameLocked(String field) {
    final map = _votes[field]!;
    if (map.isEmpty) return false;
    final total = map.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return false;
    final maxCount = map.values.reduce((a, b) => a > b ? a : b);
    return maxCount / total >= _kNameThreshold;
  }

  bool _isDateLocked(String field) {
    final window = _dateWindows[field]!;
    if (window.length < _kDateMatchRequired) return false;
    final last = window.length > _kDateWindowSize
        ? window.sublist(window.length - _kDateWindowSize)
        : window;
    final freq = <String, int>{};
    for (final v in last) {
      if (v != null) freq[v] = (freq[v] ?? 0) + 1;
    }
    if (freq.isEmpty) return false;
    final maxCount = freq.values.reduce((a, b) => a > b ? a : b);
    return maxCount >= _kDateMatchRequired;
  }

  OcrFieldResult<String> _voteResult(String field, double threshold) {
    final map = _votes[field]!;
    if (map.isEmpty) {
      return const OcrFieldResult(value: null, confidence: 0.0, locked: false);
    }
    final total = map.values.fold<int>(0, (a, b) => a + b);

    if (field == 'address') {
      return _consolidatedAddressVote(map, total, threshold);
    }

    final consolidated = _consolidatedNameVote(map, total, threshold);
    if (consolidated != null) return consolidated;

    final leading = map.entries.reduce((a, b) => a.value > b.value ? a : b);
    final confidence = total == 0 ? 0.0 : leading.value / total;
    final displayValue = _displayValues[field]?[leading.key] ?? leading.key;
    return OcrFieldResult(
      value: displayValue,
      confidence: confidence,
      locked: confidence >= threshold,
    );
  }

  OcrFieldResult<String>? _consolidatedNameVote(
    Map<String, int> map,
    int total,
    double threshold,
  ) {
    if (map.length < 2) return null;

    final entries = map.entries.toList()
      ..sort((a, b) {
        final byLen = b.key.length.compareTo(a.key.length);
        if (byLen != 0) return byLen;
        return b.value.compareTo(a.value);
      });

    final consumed = <String>{};
    final groups = <_NameGroup>[];

    for (final candidate in entries) {
      if (consumed.contains(candidate.key)) continue;
      final group = _NameGroup(
        anchor: candidate.key,
        totalVotes: candidate.value,
      );
      consumed.add(candidate.key);

      for (final other in entries) {
        if (consumed.contains(other.key)) continue;
        if (_nameIsPrefixOf(group.anchor, other.key)) {
          group.totalVotes += other.value;
          consumed.add(other.key);
        }
      }
      groups.add(group);
    }

    if (groups.length == map.length) {
      return null;
    }

    groups.sort((a, b) {
      final byVotes = b.totalVotes.compareTo(a.totalVotes);
      if (byVotes != 0) return byVotes;
      return b.anchor.length.compareTo(a.anchor.length);
    });
    final winner = groups.first;
    final field = _votes.entries.firstWhere((e) => identical(e.value, map)).key;
    final displayValue = _displayValues[field]?[winner.anchor] ?? winner.anchor;
    final confidence = total == 0 ? 0.0 : winner.totalVotes / total;
    return OcrFieldResult(
      value: displayValue,
      confidence: confidence,
      locked: confidence >= threshold,
    );
  }

  bool _nameIsPrefixOf(String anchor, String shorter) {
    if (anchor.length <= shorter.length) return false;
    if (anchor.isEmpty || shorter.isEmpty) return false;
    return anchor.startsWith('$shorter ');
  }

  OcrFieldResult<String> _consolidatedAddressVote(
    Map<String, int> map,
    int total,
    double threshold,
  ) {
    final entries = map.entries.toList()
      ..sort((a, b) {
        final byLen = b.key.length.compareTo(a.key.length);
        if (byLen != 0) return byLen;
        return b.value.compareTo(a.value);
      });

    final consumed = <String>{};
    final groups = <_AddressGroup>[];

    for (final candidate in entries) {
      if (consumed.contains(candidate.key)) continue;
      final group = _AddressGroup(
        anchor: candidate.key,
        totalVotes: candidate.value,
      );
      consumed.add(candidate.key);

      for (final other in entries) {
        if (consumed.contains(other.key)) continue;
        if (_addressVariantsAreEquivalent(group.anchor, other.key)) {
          group.totalVotes += other.value;
          consumed.add(other.key);
        }
      }
      groups.add(group);
    }

    if (groups.isEmpty) {
      return const OcrFieldResult(value: null, confidence: 0.0, locked: false);
    }

    groups.sort((a, b) {
      final byVotes = b.totalVotes.compareTo(a.totalVotes);
      if (byVotes != 0) return byVotes;
      return b.anchor.length.compareTo(a.anchor.length);
    });
    final winner = groups.first;
    final displayValue =
        _displayValues['address']?[winner.anchor] ?? winner.anchor;
    final confidence = total == 0 ? 0.0 : winner.totalVotes / total;
    final locked = total >= 2 && confidence >= threshold;
    return OcrFieldResult(
      value: displayValue,
      confidence: confidence,
      locked: locked,
    );
  }

  bool _addressVariantsAreEquivalent(String anchor, String other) {
    if (anchor.length < other.length) {
      return _addressVariantsAreEquivalent(other, anchor);
    }
    if (anchor.isEmpty || other.isEmpty) return false;

    String collapse(String s) =>
        s.toUpperCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ');
    final a = collapse(anchor);
    final o = collapse(other);
    if (a.startsWith(o)) return true;

    final dist = StringSimilarity.distance(a, o);
    final shorterLen = o.length;
    if (shorterLen == 0) return false;
    final similarity = 1.0 - (dist / shorterLen);
    return similarity >= 0.80;
  }

  String _recoverTildeFromText(String field, String mrzValue) {
    final mrzVoteKey = OcrFieldNormalizer.normalizeName(mrzValue);
    var textDisplay = _displayValues[field]?[mrzVoteKey];

    if (textDisplay == null && mrzValue.contains('XX')) {
      final mrzCollapsed = mrzValue
          .replaceAll(RegExp(r'NXX'), 'N')
          .replaceAll(RegExp(r'0$'), 'O');
      final collapsedKey = OcrFieldNormalizer.normalizeName(mrzCollapsed);
      textDisplay = _displayValues[field]?[collapsedKey];
    }

    if (textDisplay == null) return mrzValue;
    final textHasTilde = textDisplay.contains('Ñ') || textDisplay.contains('ñ');
    final mrzHasTilde = mrzValue.contains('Ñ') || mrzValue.contains('ñ');
    if (textHasTilde && !mrzHasTilde) return textDisplay;
    return mrzValue;
  }

  OcrFieldResult<String> _dateResult(String field) {
    final window = _dateWindows[field]!;
    if (window.isEmpty) {
      return const OcrFieldResult(value: null, confidence: 0.0, locked: false);
    }
    final freq = <String, int>{};
    for (final v in window) {
      if (v != null) freq[v] = (freq[v] ?? 0) + 1;
    }
    if (freq.isEmpty) {
      return const OcrFieldResult(value: null, confidence: 0.0, locked: false);
    }
    final leading = freq.entries.reduce((a, b) => a.value > b.value ? a : b);
    final locked = leading.value >= _kDateMatchRequired &&
        window.length >= _kDateMatchRequired;
    return OcrFieldResult(
      value: leading.key,
      confidence: window.isEmpty ? 0.0 : leading.value / window.length,
      locked: locked,
    );
  }

  OcrConsensusResult _buildMrzResult(MRZResult mrz) {
    String formatDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    final surnames = mrz.surnames.split(' ');
    final lastName = surnames.isNotEmpty ? surnames.first : mrz.surnames;
    final secondLastName =
        surnames.length > 1 ? surnames.sublist(1).join(' ') : null;

    final lastNameDisplay = _recoverTildeFromText('lastName', lastName);
    final firstNameDisplay = _recoverTildeFromText('firstName', mrz.givenNames);
    final secondLastNameDisplay = secondLastName != null
        ? _recoverTildeFromText('secondLastName', secondLastName)
        : null;

    final addressResult = _voteResult('address', _kAddressThreshold);

    return OcrConsensusResult(
      success: true,
      source: OcrConsensusSource.mrzChecksum,
      documentNumber: OcrFieldResult(
        value: mrz.documentNumber,
        confidence: 1.0,
        locked: true,
      ),
      firstName: OcrFieldResult(
        value: firstNameDisplay,
        confidence: 1.0,
        locked: true,
      ),
      lastName: OcrFieldResult(
        value: lastNameDisplay,
        confidence: 1.0,
        locked: true,
      ),
      secondLastName: OcrFieldResult(
        value: secondLastNameDisplay,
        confidence: secondLastNameDisplay != null ? 1.0 : 0.0,
        locked: secondLastNameDisplay != null,
      ),
      dateOfBirth: OcrFieldResult(
        value: formatDate(mrz.birthDate),
        confidence: 1.0,
        locked: true,
      ),
      expirationDate: OcrFieldResult(
        value: formatDate(mrz.expiryDate),
        confidence: 1.0,
        locked: true,
      ),
      address: addressResult,
    );
  }

  OcrConsensusResult _buildMrzResultFromFields(_MrzFieldsBuffer buf) {
    final addressResult = _voteResult('address', _kAddressThreshold);
    final firstNameVote = _voteResult('firstName', _kNameThreshold);
    final lastNameVote = _voteResult('lastName', _kNameThreshold);
    final slnVote = _voteResult('secondLastName', _kNameThreshold);
    final documentVote = _voteResult(
      'documentNumber',
      _kDocumentNumberThreshold,
    );
    final dobVote = _dateResult('dateOfBirth');
    final expVote = _dateResult('expirationDate');

    final firstNameDisplay = buf.firstName != null
        ? _recoverTildeFromText('firstName', buf.firstName!)
        : null;
    final lastNameDisplay = buf.lastName != null
        ? _recoverTildeFromText('lastName', buf.lastName!)
        : null;
    final secondLastNameDisplay = buf.secondLastName != null
        ? _recoverTildeFromText('secondLastName', buf.secondLastName!)
        : null;

    return OcrConsensusResult(
      success: true,
      source: OcrConsensusSource.mrzChecksum,
      documentNumber: OcrFieldResult(
        value: buf.documentNumber ?? documentVote.value,
        confidence: buf.documentNumber != null ? 1.0 : documentVote.confidence,
        locked: buf.documentNumber != null || documentVote.locked,
      ),
      firstName: OcrFieldResult(
        value: firstNameDisplay ?? firstNameVote.value,
        confidence: firstNameDisplay != null ? 1.0 : firstNameVote.confidence,
        locked: firstNameDisplay != null || firstNameVote.locked,
      ),
      lastName: OcrFieldResult(
        value: lastNameDisplay ?? lastNameVote.value,
        confidence: lastNameDisplay != null ? 1.0 : lastNameVote.confidence,
        locked: lastNameDisplay != null || lastNameVote.locked,
      ),
      secondLastName: OcrFieldResult(
        value: secondLastNameDisplay ?? slnVote.value,
        confidence: secondLastNameDisplay != null ? 1.0 : slnVote.confidence,
        locked: secondLastNameDisplay != null || slnVote.locked,
      ),
      dateOfBirth: OcrFieldResult(
        value: buf.dateOfBirth ?? dobVote.value,
        confidence: buf.dateOfBirth != null ? 1.0 : dobVote.confidence,
        locked: buf.dateOfBirth != null || dobVote.locked,
      ),
      expirationDate: OcrFieldResult(
        value: buf.expirationDate ?? expVote.value,
        confidence: buf.expirationDate != null ? 1.0 : expVote.confidence,
        locked: buf.expirationDate != null || expVote.locked,
      ),
      address: addressResult,
    );
  }
}

class _MrzFieldsBuffer {
  const _MrzFieldsBuffer({
    required this.documentNumber,
    required this.firstName,
    required this.lastName,
    required this.secondLastName,
    required this.dateOfBirth,
    required this.expirationDate,
  });

  final String? documentNumber;
  final String? firstName;
  final String? lastName;
  final String? secondLastName;
  final String? dateOfBirth;
  final String? expirationDate;
}

class _AddressGroup {
  _AddressGroup({required this.anchor, required this.totalVotes});

  final String anchor;
  int totalVotes;
}

class _NameGroup {
  _NameGroup({required this.anchor, required this.totalVotes});

  final String anchor;
  int totalVotes;
}
