import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Copies files into places the user's own process may not be allowed to
/// write, such as the app's own folder under `Program Files`.
///
/// Mirrors the loader task runner: the work is described as JSON, and when a
/// plain write is refused the same executable is re-run through UAC to redo
/// it. Kept separate from that runner because it carries no loader concepts —
/// it is a copy, and the loader runner returns a loader status.
class ElevatedFileCopy {
  static const String argPrefix = '--modlinq-copy=';

  /// Copies every `source -> destination` pair, elevating on Windows if the
  /// destination refuses the write.
  static Future<void> place(Map<String, String> fromTo) async {
    if (fromTo.isEmpty) return;

    try {
      copyLocal(fromTo);
      return;
    } on FileSystemException catch (e) {
      if (!Platform.isWindows || !_isPermissionError(e)) rethrow;
    }

    await _runElevated(fromTo);
  }

  /// The copy itself, free of anything a helper process cannot do.
  static void copyLocal(Map<String, String> fromTo) {
    for (final entry in fromTo.entries) {
      final target = File(entry.value);
      target.parent.createSync(recursive: true);
      File(entry.key).copySync(target.path);
    }
  }

  static bool _isPermissionError(FileSystemException e) {
    final code = e.osError?.errorCode;
    // ERROR_ACCESS_DENIED / ERROR_PRIVILEGE_NOT_HELD
    return code == 5 || code == 1314;
  }

  static Future<void> _runElevated(Map<String, String> fromTo) async {
    final dir = Directory.systemTemp.createTempSync('modlinq-copy');
    final taskFile = File(p.join(dir.path, 'copy.json'));
    final resultFile = File(p.join(dir.path, 'result.json'));

    await taskFile.writeAsString(jsonEncode(fromTo));

    final command =
        "Start-Process -FilePath '${_psQuote(Platform.resolvedExecutable)}'"
        " -ArgumentList '${_psQuote('$argPrefix${taskFile.path}')}'"
        ' -Verb RunAs -Wait';

    final process = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ]);

    try {
      if (process.exitCode != 0) {
        throw ProcessException(
          'powershell',
          const ['Start-Process -Verb RunAs'],
          'Elevated copy helper failed: ${process.stderr}',
          process.exitCode,
        );
      }

      if (!resultFile.existsSync()) {
        throw StateError('Elevated copy helper produced no result');
      }

      final json = jsonDecode(await resultFile.readAsString());
      if (json is Map && json['error'] is String) {
        throw StateError(json['error'] as String);
      }
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  /// Single quotes escape themselves in PowerShell single-quoted strings, so
  /// a path containing one would otherwise end the argument early.
  static String _psQuote(String value) => value.replaceAll("'", "''");

  /// Entry point of the elevated helper.
  static Future<void> runFromTaskFile(String taskFilePath) async {
    final resultFile = File(p.join(p.dirname(taskFilePath), 'result.json'));

    try {
      final json =
          jsonDecode(await File(taskFilePath).readAsString()) as Map;
      copyLocal(json.map((k, v) => MapEntry(k as String, v as String)));
      await resultFile.writeAsString(jsonEncode({'ok': true}));
    } catch (e) {
      await resultFile.writeAsString(jsonEncode({'error': e.toString()}));
    }
  }

  /// The `--modlinq-copy=<path>` value in [args], when this process was
  /// started as the elevated helper.
  static String? taskFileFromArgs(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith(argPrefix)) return arg.substring(argPrefix.length);
    }
    return null;
  }
}
