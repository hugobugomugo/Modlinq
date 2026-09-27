import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_log.dart';
import 'update_service.dart';

/// One thing an uninstall can remove, offered and confirmed on its own.
///
/// Split this way because the four are not equally reversible: a mod library
/// can be gigabytes the user spent hours importing, while the config is
/// throwaway. Bundling them behind one button is how people lose work.
enum UninstallStep {
  /// The loader, patched game files and installed mods inside the games.
  gameInjections,

  /// Imported mods. The expensive one.
  modLibrary,

  /// Config, logs, extracted bundle cache, cached previews.
  appData,

  /// Modlinq itself.
  application,
}

class UninstallTask {
  final UninstallStep step;

  /// One line for the confirmation dialog.
  final String label;

  /// What disappears, shown verbatim so the user can check it.
  final List<String> paths;

  /// Size on disk at plan time, for the steps that have one.
  final int bytes;

  final Future<void> Function() run;

  const UninstallTask({
    required this.step,
    required this.label,
    required this.paths,
    required this.bytes,
    required this.run,
  });
}

class UninstallPlan {
  final List<UninstallTask> tasks;

  const UninstallPlan(this.tasks);

  UninstallTask? taskFor(UninstallStep step) {
    for (final task in tasks) {
      if (task.step == step) return task;
    }
    return null;
  }
}

class UninstallFailure {
  final UninstallStep step;
  final String error;

  const UninstallFailure(this.step, this.error);
}

class UninstallOutcome {
  final List<UninstallStep> completed;
  final List<UninstallFailure> failures;

  const UninstallOutcome(this.completed, this.failures);

  bool get clean => failures.isEmpty;
}

/// Removes Modlinq and, optionally, everything it put on the machine.
///
/// The game-side and app-side removals are injected rather than reached for,
/// so this stays one readable unit and can be tested without a game install.
class UninstallService {
  final Directory appDataDir;

  /// Mod libraries. Usually one, and usually inside [appDataDir].
  final List<Directory> libraryDirs;

  final InstallKind installKind;

  /// Undoes every game-side change: loader, patched files, installed mods.
  /// Null when no game is configured.
  final Future<void> Function()? removeGameInjections;

  /// Game folders the above touches, for the dialog.
  final List<String> gameInjectionLabels;

  /// Hands over to whatever deletes the app itself and exits. Null when the
  /// app cannot remove itself, such as a package-manager install.
  final Future<void> Function()? startAppRemoval;

  const UninstallService({
    required this.appDataDir,
    required this.installKind,
    this.libraryDirs = const [],
    this.removeGameInjections,
    this.gameInjectionLabels = const [],
    this.startAppRemoval,
  });

  /// Steps that actually have something to do, in the order they must run.
  UninstallPlan plan() {
    final tasks = <UninstallTask>[];

    final injections = removeGameInjections;
    if (injections != null) {
      tasks.add(
        UninstallTask(
          step: UninstallStep.gameInjections,
          label: 'Remove the mod loader, patched files and installed mods '
              'from your games',
          paths: gameInjectionLabels,
          bytes: 0,
          run: injections,
        ),
      );
    }

    final libraries = libraryDirs.where((d) => d.existsSync()).toList();
    if (libraries.isNotEmpty) {
      tasks.add(
        UninstallTask(
          step: UninstallStep.modLibrary,
          label: 'Delete your imported mod library',
          paths: libraries.map((d) => d.path).toList(),
          bytes: libraries.fold(0, (sum, d) => sum + _sizeOf(d)),
          run: () async {
            for (final dir in libraries) {
              if (dir.existsSync()) dir.deleteSync(recursive: true);
            }
          },
        ),
      );
    }

    if (appDataDir.existsSync()) {
      tasks.add(
        UninstallTask(
          step: UninstallStep.appData,
          label: 'Delete settings, logs and cached files',
          paths: [appDataDir.path],
          bytes: _sizeOf(appDataDir),
          // Filled in by run(), which knows whether the library is being
          // kept and therefore has to survive inside this folder.
          run: () async {},
        ),
      );
    }

    final removeApp = startAppRemoval;
    if (removeApp != null && installKind != InstallKind.managed) {
      tasks.add(
        UninstallTask(
          step: UninstallStep.application,
          label: 'Uninstall Modlinq itself',
          paths: [UpdateService.installDir().path],
          bytes: 0,
          run: removeApp,
        ),
      );
    }

    return UninstallPlan(tasks);
  }

  /// Runs [selected] in plan order. A step that fails is reported and the
  /// rest still run: a locked game folder must not strand the user with a
  /// half-removed app and no way to finish.
  Future<UninstallOutcome> run(
    UninstallPlan plan,
    Set<UninstallStep> selected,
  ) async {
    final completed = <UninstallStep>[];
    final failures = <UninstallFailure>[];

    for (final task in plan.tasks) {
      if (!selected.contains(task.step)) continue;

      try {
        if (task.step == UninstallStep.appData) {
          _removeAppData(keepLibraries: !selected.contains(
            UninstallStep.modLibrary,
          ));
        } else {
          await task.run();
        }

        completed.add(task.step);
        AppLog.info('Uninstall step done: ${task.step.name}');
      } catch (e, stack) {
        failures.add(UninstallFailure(task.step, '$e'));
        AppLog.error(
          'Uninstall step failed: ${task.step.name}',
          error: e,
          stack: stack,
        );
      }
    }

    return UninstallOutcome(completed, failures);
  }

  /// Deletes the app data folder, optionally carving out libraries that live
  /// inside it. The default library does, so "keep my mods, drop my settings"
  /// has to be possible without moving gigabytes first.
  void _removeAppData({required bool keepLibraries}) {
    if (!appDataDir.existsSync()) return;

    final kept = keepLibraries
        ? libraryDirs
              .where((d) => d.existsSync() && _isInside(d, appDataDir))
              .map((d) => p.canonicalize(d.path))
              .toSet()
        : <String>{};

    if (kept.isEmpty) {
      appDataDir.deleteSync(recursive: true);
      return;
    }

    for (final entry in appDataDir.listSync(followLinks: false)) {
      final path = p.canonicalize(entry.path);
      if (kept.any((k) => k == path || p.isWithin(path, k))) continue;

      entry.deleteSync(recursive: entry is Directory);
    }
  }

  static bool _isInside(Directory child, Directory parent) =>
      p.isWithin(p.canonicalize(parent.path), p.canonicalize(child.path));

  static int _sizeOf(Directory dir) {
    if (!dir.existsSync()) return 0;

    var total = 0;
    for (final entry in dir.listSync(recursive: true, followLinks: false)) {
      if (entry is File) {
        try {
          total += entry.lengthSync();
        } catch (_) {
          // A file that vanished mid-scan simply does not count.
        }
      }
    }
    return total;
  }
}
