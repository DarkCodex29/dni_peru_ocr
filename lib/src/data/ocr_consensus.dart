import 'package:mrz_parser/mrz_parser.dart';

import 'ocr_field_normalizer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Value types
// ─────────────────────────────────────────────────────────────────────────────

/// Result for a single OCR field after consensus.
class OcrFieldResult<T> {
  const OcrFieldResult({
    required this.value,
    required this.confidence,
    required this.locked,
  });

  /// The best-effort value for this field (may be null if no data yet).
  final T? value;

  /// Confidence level 0.0–1.0.
  final double confidence;

  /// Whether the field has crossed its locking threshold.
  final bool locked;
}

/// Source that triggered the consensus lock.
enum OcrConsensusSource {
  /// Locked via ≥2 consecutive MRZ checksum-valid parses.
  mrzChecksum,

  /// Locked via temporal vote accumulation threshold.
  temporalVote,

  /// Manual fallback — caller forced a snapshot before full consensus.
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

  /// True when all mandatory fields are locked.
  final bool success;

  /// What triggered this result.
  final OcrConsensusSource source;

  final OcrFieldResult<String> documentNumber;
  final OcrFieldResult<String> firstName;
  final OcrFieldResult<String> lastName;
  final OcrFieldResult<String> secondLastName;
  final OcrFieldResult<String> dateOfBirth;
  final OcrFieldResult<String> expirationDate;
  final OcrFieldResult<String> address;
}

// ─────────────────────────────────────────────────────────────────────────────
// Consensus builder
// ─────────────────────────────────────────────────────────────────────────────

/// Per-field thresholds (vote ratio required to lock).
const _kDocumentNumberThreshold = 0.95;
const _kNameThreshold = 0.80;
const _kAddressThreshold = 0.60;

/// For date fields: match required in N of last M frames.
const _kDateMatchRequired = 4;
const _kDateWindowSize = 5;

/// Consecutive MRZ parses required for fast-lock.
const _kMrzConsecutiveRequired = 2;

/// Accumulates OCR consensus by collecting per-field votes across frames.
///
/// Call [recordVote] for each processed frame with a map of field→value.
/// Call [recordMrz] when `mrz_parser` returns a checksum-valid result.
/// Call [checkAllThresholds] to see if consensus is reached.
/// Call [snapshot] to emit the current [OcrConsensusResult].
/// Call [dispose] when done (currently a no-op, included for future timers).
class OcrConsensusAccumulator {
  // ── Vote maps: field → (normalizedValue → count) ─────────────────────────
  final Map<String, Map<String, int>> _votes = {
    'documentNumber': {},
    'firstName': {},
    'lastName': {},
    'secondLastName': {},
    'address': {},
  };

  /// Parallel map: field → (voteKey → displayValue).
  /// Keyed identically to [_votes] but holds the tilde-preserving variant
  /// (output of [OcrFieldNormalizer.normalizeForDisplay]). Used so that
  /// `MUNXXOZ`, `MUNOZ`, and `MUÑOZ` collapse to the same vote bucket while
  /// still surfacing `MUÑOZ` as the stored result.
  ///
  /// Upgrade rule on insert:
  ///   - if missing → set
  ///   - else if new displayValue contains `Ñ`/`ñ` AND current does not → replace
  ///   - else → keep current
  final Map<String, Map<String, String>> _displayValues = {
    'documentNumber': {},
    'firstName': {},
    'lastName': {},
    'secondLastName': {},
    'address': {},
  };

  // ── Date sliding windows: field → list of last N raw values ──────────────
  final Map<String, List<String?>> _dateWindows = {
    'dateOfBirth': [],
    'expirationDate': [],
  };

  // ── MRZ fast-lock tracking ────────────────────────────────────────────────
  int _consecutiveMrzCount = 0;

  // ── Lock state ────────────────────────────────────────────────────────────
  bool _mrzLocked = false;
  MRZResult? _lockedMrz;

  /// Records OCR field votes for one processed frame.
  ///
  /// [fields] is a map of field name → raw OCR value (null/empty = no data).
  /// Keys: `documentNumber`, `firstName`, `lastName`, `dateOfBirth`,
  ///       `expirationDate`, `address`.
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

  /// Inserts or upgrades the display value for ([field], [voteKey]).
  ///
  /// Only name fields are tilde-bearing; other fields fall back to a
  /// simple trim/uppercase via [OcrFieldNormalizer.normalizeForDisplay]
  /// so the map always has a value to return.
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

  /// Picks the right display normalizer for the field:
  /// name fields preserve `Ñ`; others use minimal trim-only logic
  /// (document numbers and addresses must NOT be uppercased here — they
  /// already have their own normalizers in [_normalize] and we only need
  /// a non-empty fallback display value).
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
  ///
  /// After [_kMrzConsecutiveRequired] consecutive valid parses, all MRZ
  /// fields are fast-locked, overriding any text-OCR votes.
  void recordMrz(MRZResult mrz) {
    if (_mrzLocked) return;
    _consecutiveMrzCount++;

    if (_consecutiveMrzCount >= _kMrzConsecutiveRequired) {
      _mrzLocked = true;
      _lockedMrz = mrz;
    }
  }

  /// Fast-locks consensus from MRZ-extracted fields when the extractor
  /// already parsed the MRZ (and a raw [MRZResult] is not available).
  /// Locks after [_kMrzConsecutiveRequired] consecutive observations.
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
    _mrzFieldsBuffer = _MrzFieldsBuffer(
      documentNumber: documentNumber,
      firstName: firstName,
      lastName: lastName,
      secondLastName: secondLastName,
      dateOfBirth: dateOfBirth,
      expirationDate: expirationDate,
    );
    if (_consecutiveMrzCount >= _kMrzConsecutiveRequired) {
      _mrzLocked = true;
    }
  }

  /// Resets the MRZ consecutive counter so partial detections in non-MRZ
  /// frames do not accumulate toward the lock threshold.
  /// The buffer is intentionally preserved — Peruvian DNI azul holograms
  /// produce intermittent MRZ frames, so the last-seen fields stay
  /// available for [snapshot] even while the consecutive counter resets.
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
  ///
  /// If [checkAllThresholds] is false, emits a partial result with
  /// `success = false` and `source = manualFallback`.
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

  /// Releases resources. Call when the OCR pipeline is disposed.
  void dispose() {
    // No-op currently. Placeholder for future timer cancellation.
  }

  // ── Private helpers ───────────────────────────────────────────────────────

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
    // Count matches for the most frequent value in last window
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
    final leading = map.entries.reduce((a, b) => a.value > b.value ? a : b);
    final confidence = total == 0 ? 0.0 : leading.value / total;
    // Prefer the tilde-preserving display value; fall back to the ASCII
    // vote-key when the display map has nothing recorded (defensive — the
    // upgrade rule in [_updateDisplayValue] guarantees it exists).
    final displayValue = _displayValues[field]?[leading.key] ?? leading.key;
    return OcrFieldResult(
      value: displayValue,
      confidence: confidence,
      locked: confidence >= threshold,
    );
  }

  /// Looks up a tilde-bearing display value to upgrade an MRZ-provided name.
  /// Returns [mrzValue] unchanged unless text-OCR voted a `Ñ`/`ñ` variant of
  /// the same ASCII root.
  String _recoverTildeFromText(String field, String mrzValue) {
    final mrzVoteKey = OcrFieldNormalizer.normalizeName(mrzValue);
    final textDisplay = _displayValues[field]?[mrzVoteKey];
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
    final locked =
        leading.value >= _kDateMatchRequired &&
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
    final secondLastName = surnames.length > 1
        ? surnames.sublist(1).join(' ')
        : null;

    // Recover tildes that the MRZ stripped, when text-OCR has them
    // in its display map for the same ASCII root.
    final lastNameDisplay = _recoverTildeFromText('lastName', lastName);
    final firstNameDisplay = _recoverTildeFromText('firstName', mrz.givenNames);
    final secondLastNameDisplay = secondLastName != null
        ? _recoverTildeFromText('secondLastName', secondLastName)
        : null;

    // Best-effort address from text-OCR votes
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
    final slnVote = _voteResult('secondLastName', _kNameThreshold);

    // Prefer the tilde-bearing variant that text-OCR may have recorded
    // for the same ASCII root.
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
        value: buf.documentNumber,
        confidence: 1.0,
        locked: buf.documentNumber != null,
      ),
      firstName: OcrFieldResult(
        value: firstNameDisplay,
        confidence: 1.0,
        locked: firstNameDisplay != null,
      ),
      lastName: OcrFieldResult(
        value: lastNameDisplay,
        confidence: 1.0,
        locked: lastNameDisplay != null,
      ),
      secondLastName: OcrFieldResult(
        value: secondLastNameDisplay ?? slnVote.value,
        confidence: secondLastNameDisplay != null ? 1.0 : slnVote.confidence,
        locked: secondLastNameDisplay != null || slnVote.locked,
      ),
      dateOfBirth: OcrFieldResult(
        value: buf.dateOfBirth,
        confidence: 1.0,
        locked: buf.dateOfBirth != null,
      ),
      expirationDate: OcrFieldResult(
        value: buf.expirationDate,
        confidence: 1.0,
        locked: buf.expirationDate != null,
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

/// Deprecated alias for [OcrConsensusAccumulator].
///
/// The class was renamed from `OcrConsensusBuilder` to `OcrConsensusAccumulator`
/// in v0.6.0 to reflect its actual role (accumulating votes, not building a
/// new object via a builder pattern). Replace usages with [OcrConsensusAccumulator].
///
/// TODO(0.7.0): Remove this alias.
@Deprecated(
  'Use OcrConsensusAccumulator instead. '
  'OcrConsensusBuilder will be removed in v0.7.0.',
)
typedef OcrConsensusBuilder = OcrConsensusAccumulator;
