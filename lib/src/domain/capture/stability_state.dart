import 'dart:math' as math;

/// Pure helper for the document stability counter.
///
/// Encapsulates the update logic for the stable-frame counter so it can be
/// tested independently from any camera image stream.
///
/// The [update] method receives the current counter value, the absolute
/// block-count diff between frames, and an isEmpty flag. It returns the
/// new counter value.
class StabilityState {
  const StabilityState._();

  /// Returns the next value of the stability counter.
  ///
  /// A frame is "stable" when [blockDiff] is at most 2 AND [isEmpty] is false.
  /// Stable frames increment the counter by 1; unstable frames decrement it
  /// by 1, floored at 0.
  static int update({
    required int current,
    required int blockDiff,
    required bool isEmpty,
  }) {
    if (blockDiff <= 2 && !isEmpty) {
      return current + 1;
    }
    return math.max(0, current - 1);
  }
}
