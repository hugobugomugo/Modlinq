import 'dart:io';

/// Answers whether a game binary is currently running.
///
/// The mod loader is a DLL the game maps at process start, so a loader this
/// app writes while the game is already up does nothing until the next launch.
/// Without this check that is a silent no-op: the app reports success, the
/// game stays vanilla, and the user has no way to connect the two.
class GameProcessWatch {
  /// Lists processes matching an image name. Replaced in tests.
  final Future<ProcessResult> Function(String exe) _list;

  /// Whether this platform can be asked at all. Only Windows runs the game as
  /// a host process under its own name; elsewhere it sits behind a compat
  /// layer, and a wrong answer is worse than none.
  final bool _supported;

  GameProcessWatch({
    Future<ProcessResult> Function(String exe)? list,
    bool? supported,
  })  : _list = list ?? _tasklist,
        _supported = supported ?? Platform.isWindows;

  static Future<ProcessResult> _tasklist(String exe) =>
      Process.run('tasklist', ['/NH', '/FI', 'IMAGENAME eq $exe']);

  /// True when [exe] shows up in the process list. Never throws: a failed
  /// lookup means "unknown", and unknown is treated as not running.
  Future<bool> isRunning(String exe) async {
    if (!_supported || exe.isEmpty) return false;

    try {
      final result = await _list(exe);
      return result.stdout.toString().toLowerCase().contains(exe.toLowerCase());
    } catch (_) {
      return false;
    }
  }
}
