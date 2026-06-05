import 'package:mrz_parser/mrz_parser.dart';

import 'ocr_field_normalizer.dart';
import 'string_similarity.dart';

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

/// Consecutive MRZ parses required for fast-lock (default).
///
/// 2 frames at 30fps ≈ 66ms — enough for the back side of older booklet DNIs.
/// For the electronic DNI back side, raise this via the
/// [OcrConsensusAccumulator.mrzConsecutiveRequired] constructor parameter
/// to give the camera more time to stabilize before triggering capture
/// (mitigates motion blur — BUG 2, obs #4669).
const _kMrzConsecutiveRequired = 2;

/// Accumulates OCR consensus by collecting per-field votes across frames.
///
/// Call [recordVote] for each processed frame with a map of field→value.
/// Call [recordMrz] when `mrz_parser` returns a checksum-valid result.
/// Call [checkAllThresholds] to see if consensus is reached.
/// Call [snapshot] to emit the current [OcrConsensusResult].
/// Call [dispose] when done (currently a no-op, included for future timers).
class OcrConsensusAccumulator {
  /// Creates an accumulator.
  ///
  /// [mrzConsecutiveRequired] sets how many consecutive MRZ-valid frames are
  /// required before the accumulator marks itself MRZ-locked (which the
  /// host widget typically uses to trigger `takePicture()`). Defaults to 2
  /// for backwards compatibility. Recommended values:
  ///  - 2 — booklet DNI back side or front (legacy).
  ///  - 5 — electronic DNI back side (~165ms stability window to avoid
  ///        motion blur in the captured still). Fix for BUG 2 (obs #4669).
  OcrConsensusAccumulator({this.mrzConsecutiveRequired = _kMrzConsecutiveRequired})
      : assert(mrzConsecutiveRequired >= 1,
            'mrzConsecutiveRequired must be >= 1');

  /// How many consecutive MRZ-valid frames are required to fast-lock.
  final int mrzConsecutiveRequired;

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
  /// After [mrzConsecutiveRequired] consecutive valid parses, all MRZ
  /// fields are fast-locked, overriding any text-OCR votes.
  void recordMrz(MRZResult mrz) {
    if (_mrzLocked) return;
    _consecutiveMrzCount++;

    if (_consecutiveMrzCount >= mrzConsecutiveRequired) {
      _mrzLocked = true;
      _lockedMrz = mrz;
    }
  }

  /// Fast-locks consensus from MRZ-extracted fields when the extractor
  /// already parsed the MRZ (and a raw [MRZResult] is not available).
  /// Locks after [mrzConsecutiveRequired] consecutive observations.
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
    // Merge with the previous buffer instead of overwriting: a later frame
    // with the MRZ checksum still valid but a garbled name line must NOT
    // erase the fields captured by an earlier clean frame.
    // Fix for BUG 3B (obs #4673).
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

    // Address-specific consolidation: ML Kit emits the same address in many
    // micro-variants across frames (`MILAGRO MZ`, `MILAGRO MZ.B`, `MILAGRO
    // MZ.B LT.19`, `MLAGRO MZ.B LT.19`...). The previous logic gave each
    // variant its own bucket, so a `reduce(max)` over single-vote buckets
    // returned a non-deterministic winner — often the corrupted variant.
    //
    // We consolidate by grouping buckets that share a normalized prefix:
    // shorter variants merge into their longer SUPERSTRING when the
    // shorter is a tilde-insensitive prefix of the longer's first N tokens.
    // Among the consolidated group, we prefer the LONGEST string (most
    // preserved OCR data) and sum the vote counts.
    if (field == 'address') {
      return _consolidatedAddressVote(map, total, threshold);
    }

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

  /// Consolidates address votes by grouping near-duplicate variants.
  ///
  /// Strategy:
  ///   1. Sort buckets by string length descending.
  ///   2. For each bucket starting from the longest, absorb every shorter
  ///      bucket whose first tokens are a tilde-insensitive prefix of the
  ///      longer string, OR whose Levenshtein similarity to the longer
  ///      string is ≥ 0.80 over the common length.
  ///   3. The longest string in each group wins; its absorbed votes sum.
  ///   4. Return the group with the highest combined vote count.
  ///
  /// This prevents OCR micro-variants (`MILAGRO MZ` vs `MLAGRO MZ.B LT.19`
  /// vs `MILAGRO MZ.B LT.19`) from each landing in a separate single-vote
  /// bucket and producing a non-deterministic `reduce(max)` winner.
  OcrFieldResult<String> _consolidatedAddressVote(
    Map<String, int> map,
    int total,
    double threshold,
  ) {
    // Snapshot entries sorted by length descending so the longest seeds
    // each group.
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
    return OcrFieldResult(
      value: displayValue,
      confidence: confidence,
      locked: confidence >= threshold,
    );
  }

  /// Returns true when [shorter] is plausibly the same address as [longer]:
  ///   - same upper-cased length-normalized prefix (`MILAGRO MZ` is a prefix
  ///     of `MILAGRO MZ.B LT.19` after collapsing whitespace + dots), OR
  ///   - Levenshtein similarity ≥ 0.80 over the SHORTER string's length
  ///     (catches single-character OCR glitches like `MILAGRO` vs `MLAGRO`).
  ///
  /// `shorter` here means the second argument; the caller groups around the
  /// longest anchor first, so [other] should never be longer than [anchor].
  bool _addressVariantsAreEquivalent(String anchor, String other) {
    if (anchor.length < other.length) {
      // Caller should pass anchor as the longer; defensive swap is a no-op
      // for correctness because the prefix check below is symmetric.
      return _addressVariantsAreEquivalent(other, anchor);
    }
    if (anchor.isEmpty || other.isEmpty) return false;

    // Collapse runs of whitespace and remove dots for prefix comparison.
    String collapse(String s) =>
        s.toUpperCase().replaceAll('.', '').replaceAll(RegExp(r'\s+'), ' ');
    final a = collapse(anchor);
    final o = collapse(other);
    if (a.startsWith(o)) return true;

    // Fuzzy: distance over the shorter length. ≤ 20% character edits.
    final dist = StringSimilarity.distance(a, o);
    final shorterLen = o.length;
    if (shorterLen == 0) return false;
    final similarity = 1.0 - (dist / shorterLen);
    return similarity >= 0.80;
  }

  /// Looks up a tilde-bearing display value to upgrade an MRZ-provided name.
  /// Returns [mrzValue] unchanged unless text-OCR voted a `Ñ`/`ñ` variant of
  /// the same ASCII root, OR a text-OCR variant that matches after collapsing
  /// the RENIEC `NXX` placeholder back to `N` (Peruvian MRZ encodes `Ñ` as
  /// `NXX` because ICAO 9303 has no `Ñ` codepoint — `ERMITAÑO` → `ERMITANXXO`).
  String _recoverTildeFromText(String field, String mrzValue) {
    // Try direct normalised match first (handles plain accents Á É Í Ó Ú).
    final mrzVoteKey = OcrFieldNormalizer.normalizeName(mrzValue);
    var textDisplay = _displayValues[field]?[mrzVoteKey];

    // Peruvian MRZ Ñ recovery: collapse `NXX` → `N` and trailing `0` → `O`
    // BEFORE normalising, so `ERMITANXX0` becomes `ERMITANO` which matches
    // the text-OCR vote key for `ERMITAÑO` (both normalise to `ERMITANO`).
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
    // Vote-map fallbacks for the name fields. If the MRZ buffer is null on
    // any name (because the back-side MRZ block was partial), fall back to
    // text-OCR votes accumulated from the front-side seed or earlier frames.
    // Fix for BUG 3A (obs #4673): firstName/lastName were previously asymmetric
    // vs secondLastName — only the latter fell back to votes.
    final firstNameVote = _voteResult('firstName', _kNameThreshold);
    final lastNameVote = _voteResult('lastName', _kNameThreshold);
    final slnVote = _voteResult('secondLastName', _kNameThreshold);
    final documentVote = _voteResult(
      'documentNumber',
      _kDocumentNumberThreshold,
    );
    final dobVote = _dateResult('dateOfBirth');
    final expVote = _dateResult('expirationDate');

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

/// Internal: a group of address vote-keys that all represent the same
/// underlying address, with their summed vote count.
class _AddressGroup {
  _AddressGroup({required this.anchor, required this.totalVotes});
  final String anchor;
  int totalVotes;
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
