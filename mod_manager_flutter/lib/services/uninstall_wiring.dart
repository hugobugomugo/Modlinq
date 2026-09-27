import 'dart:io';

import 'package:path/path.dart' as p;

import '../games/deadlock/deadlock_manager.dart';
import '../utils/path_helper.dart';
import 'app_log.dart';
import 'app_remover.dart';
import 'config_service.dart';
import 'nte_loader_service.dart';
import 'nte_mod_manager.dart';
import 'platform_service_factory.dart';
import 'uninstall_service.dart';
import 'update_service.dart';

/// Builds an [UninstallService] against the real installation.
///
/// Kept out of [UninstallService] so that stays testable without a game, a
/// config store or a platform service.
class UninstallWiring {
  static Future<UninstallService> forApp(ConfigService config) async {
    final labels = _gameLabels(config);

    return UninstallService(
      appDataDir: Directory(PathHelper.getAppDataPath()),
      libraryDirs: _libraryDirs(config),
      installKind: await UpdateService.detectInstallKind(),
      gameInjectionLabels: labels,
      removeGameInjections: labels.isEmpty
          ? null
          : () => _removeInjections(config),
      startAppRemoval: AppRemover.start,
    );
  }

  static List<Directory> _libraryDirs(ConfigService config) {
    final paths = <String>{
      NteModManager.resolveLibraryPath(config),
      if (config.deadlockLibraryPath case final path? when path.isNotEmpty)
        path,
    };

    return paths
        .map(Directory.new)
        .where((dir) => dir.existsSync())
        .toList();
  }

  /// Game folders an uninstall would touch, shown in the confirmation.
  static List<String> _gameLabels(ConfigService config) => [
    if (config.nteGamePath case final path? when path.isNotEmpty)
      'Neverness to Everness: $path',
    if (config.deadlockGamePath case final path? when path.isNotEmpty)
      'Deadlock: $path',
    if (config.zzzSaveModsPath case final path? when path.isNotEmpty)
      'Zenless Zone Zero: $path',
    if (config.wwSaveModsPath case final path? when path.isNotEmpty)
      'Wuthering Waves: $path',
  ];

  /// Undoes every game-side change. One game failing never stops the others:
  /// a locked folder for one title must not leave the other three patched.
  static Future<void> _removeInjections(ConfigService config) async {
    final failures = <String>[];

    await _attempt(failures, 'NTE', () async {
      final loader = NteLoaderService.fromConfig(config);
      if (loader == null) return;

      final manager = NteModManager.fromConfig(config);
      final asiNames = manager == null
          ? const <String>[]
          : manager
                .listMods()
                .where((mod) => mod.isAsi)
                .expand((mod) => mod.files.map(p.basename))
                .toList();

      await loader.clean(installedAsiNames: asiNames);
    });

    await _attempt(failures, 'Deadlock', () async {
      final manager = DeadlockModManager.fromConfig(config);
      if (manager == null) return;

      for (final mod in manager.listMods().where((mod) => mod.enabled)) {
        await manager.setEnabled(mod.name, false);
      }

      // Last, so the search path only goes away once nothing needs it.
      manager.gameinfo.unpatch();
    });

    await _attempt(failures, 'ZZZ', () => _removeLinks(config.zzzSaveModsPath));
    await _attempt(failures, 'WuWa', () => _removeLinks(config.wwSaveModsPath));

    if (failures.isNotEmpty) {
      throw StateError('could not fully clean: ${failures.join('; ')}');
    }
  }

  /// ZZZ and Wuthering Waves install mods as symlinks into the game's mods
  /// folder, so undoing them is removing the links and nothing else. Real
  /// folders in there belong to the user and are left alone.
  static Future<void> _removeLinks(String? saveModsPath) async {
    if (saveModsPath == null || saveModsPath.isEmpty) return;

    final dir = Directory(saveModsPath);
    if (!dir.existsSync()) return;

    final platform = PlatformServiceFactory.getInstance();
    for (final entry in dir.listSync(followLinks: false)) {
      if (!await platform.isModLink(entry.path)) continue;
      await platform.removeModLink(entry.path);
    }
  }

  static Future<void> _attempt(
    List<String> failures,
    String what,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e, stack) {
      failures.add('$what ($e)');
      AppLog.error('Uninstall cleanup failed for $what', error: e, stack: stack);
    }
  }
}
