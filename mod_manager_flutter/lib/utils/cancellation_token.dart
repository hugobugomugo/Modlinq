/// A one-way flag saying the work it was handed to is no longer wanted.
///
/// Dart futures cannot be killed from outside, so long scans cooperate instead:
/// they check [isCancelled] at their loop boundaries and give up early. Loading
/// 160 mods means hundreds of sequential filesystem calls, and without this a
/// game switch has to sit through all of them before the new game can load.
class CancellationToken {
  bool _cancelled = false;

  /// Whether the work should stop at the next opportunity.
  bool get isCancelled => _cancelled;

  /// Marks the work as unwanted. Cancelling twice is harmless.
  void cancel() => _cancelled = true;

  /// Null-tolerant read, for APIs where the token is optional.
  static bool isCancelledOrNull(CancellationToken? token) =>
      token?.isCancelled ?? false;
}
