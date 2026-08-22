import 'dart:async';

import 'cancellation_token.dart';

/// Serialises reload requests so one made mid-flight is never lost, and lets
/// the running one know it has been overtaken.
///
/// A plain `if (busy) return;` guard drops the request instead of deferring it,
/// which is how switching game during a slow mod load used to leave the grid on
/// the previous game forever. Here the request is remembered and replayed once
/// the running task finishes.
///
/// Only the newest waiting request survives: three switches during one load
/// replay once, for the game the user actually landed on.
///
/// Each task is handed a [CancellationToken] that is cancelled the moment a
/// newer request arrives, so the outgoing load can abandon its remaining work
/// rather than making the user sit through it.
class ReloadQueue {
  bool _running = false;
  CancellationToken? _token;
  Future<void> Function(CancellationToken)? _pending;

  /// Whether a task is in flight right now.
  bool get isRunning => _running;

  /// Whether a newer request is already waiting.
  ///
  /// The running task should check this before applying its results: a true
  /// here means the user has moved on and those results are stale.
  bool get isSuperseded => _pending != null;

  /// Runs [task], or defers it when another task is already running.
  ///
  /// Returns as soon as the request is recorded, so a deferred request does not
  /// block its caller on the task already in flight.
  Future<void> run(Future<void> Function(CancellationToken) task) async {
    if (_running) {
      _pending = task;
      _token?.cancel();
      return;
    }

    _running = true;
    try {
      var next = task;
      while (true) {
        final token = CancellationToken();
        _token = token;

        try {
          await next(token);
        } catch (_) {
          // A failure only matters when it is still the newest request;
          // otherwise the replay about to run supersedes it anyway.
          if (_pending == null) rethrow;
        }

        final queued = _pending;
        if (queued == null) return;
        _pending = null;
        next = queued;
      }
    } finally {
      _running = false;
      _pending = null;
      _token = null;
    }
  }
}
