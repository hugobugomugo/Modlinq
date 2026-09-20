import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bundled_files.dart';
import 'nte_bundled_mods.dart';
import 'nte_game_detection.dart';
import 'nte_loader_installer.dart';

/// Loader operations that touch the game folder.
enum NteLoaderTaskKind { install, uninstall, clean, bundledMod }

/// A loader operation described well enough to be handed to another process.
///
/// On Windows the game usually lives under `Program Files`, where writing
/// needs elevation, so the task is serialised to JSON and re-run by an
/// elevated copy of this same executable.
class NteLoaderTask {
  final NteLoaderTaskKind kind;
  final String gameRoot;
  final NteEdition edition;

  /// Folder the bundled assets were extracted to, readable by the helper.
  final String assetRoot;

  /// `.asi` mod file names to delete as well, only used by [NteLoaderTaskKind.clean].
  final List<String> installedAsiNames;

  /// Which bundled extra to toggle, only used by [NteLoaderTaskKind.bundledMod].
  final NteBundledMod? bundledMod;

  /// Desired state of [bundledMod].
  final bool bundledEnabled;

  const NteLoaderTask({
    required this.kind,
    required this.gameRoot,
    required this.edition,
    required this.assetRoot,
    this.installedAsiNames = const [],
    this.bundledMod,
    this.bundledEnabled = false,
  });

  static const String argPrefix = '--nte-loader-task=';

  static NteBundledMod? _bundledModFromName(String? name) {
    for (final value in NteBundledMod.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'gameRoot': gameRoot,
    'edition': edition.key,
    'assetRoot': assetRoot,
    'installedAsiNames': installedAsiNames,
    'bundledMod': bundledMod?.name,
    'bundledEnabled': bundledEnabled,
  };

  static NteLoaderTask fromJson(Map<String, dynamic> json) => NteLoaderTask(
    kind: NteLoaderTaskKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => NteLoaderTaskKind.install,
    ),
    gameRoot: json['gameRoot'] as String? ?? '',
    edition: NteEdition.values.firstWhere(
      (value) => value.key == json['edition'],
      orElse: () => NteEdition.unknown,
    ),
    assetRoot: json['assetRoot'] as String? ?? '',
    installedAsiNames:
        (json['installedAsiNames'] as List?)?.cast<String>() ?? const [],
    bundledMod: _bundledModFromName(json['bundledMod'] as String?),
    bundledEnabled: json['bundledEnabled'] as bool? ?? false,
  );
}

/// Runs [NteLoaderTask]s, elevating on Windows when the folder needs it.
class NteLoaderTaskRunner {
  /// Performs [task] in this process.
  static Future<NteLoaderStatus> runLocal(NteLoaderTask task) async {
    final installer = NteLoaderInstaller(
      gameRoot: task.gameRoot,
      edition: task.edition,
      source: DirectoryFileSource(task.assetRoot),
    );

    switch (task.kind) {
      case NteLoaderTaskKind.install:
        return installer.install();
      case NteLoaderTaskKind.uninstall:
        return installer.uninstall();
      case NteLoaderTaskKind.clean:
        installer.cleanGameMods(installedAsiNames: task.installedAsiNames);
        NteBundledModsInstaller(
          gameRoot: task.gameRoot,
          source: DirectoryFileSource(task.assetRoot),
          loader: installer,
        ).removeAll();
        return installer.status();
      case NteLoaderTaskKind.bundledMod:
        final mod = task.bundledMod;
        if (mod == null) throw StateError('No bundled mod given');

        await NteBundledModsInstaller(
          gameRoot: task.gameRoot,
          source: DirectoryFileSource(task.assetRoot),
          loader: installer,
        ).setEnabled(mod, task.bundledEnabled);

        return installer.status();
    }
  }

  /// Performs [task], retrying through an elevated helper when the game folder
  /// refuses the write. Only Windows has that helper; elsewhere the failure is
  /// the user's own permissions and is surfaced as-is.
  static Future<NteLoaderStatus> run(NteLoaderTask task) async {
    try {
      return await runLocal(task);
    } on FileSystemException catch (e) {
      if (!Platform.isWindows || !_isPermissionError(e)) rethrow;
      return runElevated(task);
    }
  }

  static bool _isPermissionError(FileSystemException e) {
    final code = e.osError?.errorCode;
    // ERROR_ACCESS_DENIED / ERROR_PRIVILEGE_NOT_HELD
    return code == 5 || code == 1314;
  }

  /// Relaunches this executable through UAC to redo [task] as administrator.
  static Future<NteLoaderStatus> runElevated(NteLoaderTask task) async {
    final dir = Directory.systemTemp.createTempSync('modlinq-loader');
    final taskFile = File(p.join(dir.path, 'task.json'));
    final resultFile = File(p.join(dir.path, 'result.json'));

    await taskFile.writeAsString(jsonEncode(task.toJson()));

    final command =
        "Start-Process -FilePath '${_psQuote(Platform.resolvedExecutable)}'"
        " -ArgumentList '${_psQuote('${NteLoaderTask.argPrefix}${taskFile.path}')}'"
        ' -Verb RunAs -Wait';

    final process = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ]);

    if (process.exitCode != 0) {
      dir.deleteSync(recursive: true);
      throw ProcessException(
        'powershell',
        const ['Start-Process -Verb RunAs'],
        'Elevated loader helper failed: ${process.stderr}',
        process.exitCode,
      );
    }

    if (!resultFile.existsSync()) {
      dir.deleteSync(recursive: true);
      throw StateError('Elevated loader helper produced no result');
    }

    final json = jsonDecode(await resultFile.readAsString());
    dir.deleteSync(recursive: true);

    if (json is Map<String, dynamic> && json['error'] is String) {
      throw StateError(json['error'] as String);
    }

    return NteLoaderStatus.fromJson(json as Map<String, dynamic>);
  }

  /// Single quotes are the escape character in PowerShell single-quoted
  /// strings, so a path containing one would otherwise end the argument.
  static String _psQuote(String value) => value.replaceAll("'", "''");

  /// Entry point of the elevated helper: the task file sits next to the file
  /// the result is written to, so the parent knows where to look.
  static Future<void> runFromTaskFile(String taskFilePath) async {
    final resultFile = File(p.join(p.dirname(taskFilePath), 'result.json'));

    try {
      final json =
          jsonDecode(await File(taskFilePath).readAsString())
              as Map<String, dynamic>;
      final status = await runLocal(NteLoaderTask.fromJson(json));

      await resultFile.writeAsString(jsonEncode(status.toJson()));
    } catch (e) {
      await resultFile.writeAsString(jsonEncode({'error': e.toString()}));
    }
  }

  /// The `--nte-loader-task=<path>` value in [args], if this process was
  /// started as the elevated helper.
  static String? taskFileFromArgs(List<String> args) {
    for (final arg in args) {
      if (arg.startsWith(NteLoaderTask.argPrefix)) {
        return arg.substring(NteLoaderTask.argPrefix.length);
      }
    }
    return null;
  }
}
