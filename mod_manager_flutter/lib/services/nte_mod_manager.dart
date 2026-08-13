import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/nte_mod.dart';
import '../utils/path_helper.dart';
import 'config_service.dart';
import 'nte_mod_installer.dart';
import 'nte_mod_library.dart';

/// Coordinates the NTE mod library, the game folder and stored settings.
///
/// The game folder is treated as derived state: enabled mods are whatever is
/// currently installed there. Settings only record intent, so a mod the game
/// had locked is retried on the next apply.
class NteModManager {
  final NteModLibrary library;
  final NteModInstaller installer;
  final ConfigService config;

  NteModManager({
    required this.library,
    required this.installer,
    required this.config,
  });

  /// Builds a manager from stored config. Returns null when no valid game
  /// folder is configured yet.
  static NteModManager? fromConfig(ConfigService config) {
    final gamePath = config.nteGamePath;
    if (gamePath == null || gamePath.isEmpty) return null;

    return NteModManager(
      library: NteModLibrary(resolveLibraryPath(config)),
      installer: NteModInstaller(gamePath),
      config: config,
    );
  }

  /// Where imported mods are stored. Defaults to a folder in the app data
  /// directory so the library survives game reinstalls.
  static String resolveLibraryPath(ConfigService config) {
    final configured = config.nteLibraryPath;
    if (configured != null && configured.isNotEmpty) return configured;

    return p.join(PathHelper.getAppDataPath(), 'nte_mods');
  }

  /// All library mods, with their category and live installed state.
  List<NteMod> listMods() {
    final categories = config.nteModCategories;

    return library
        .listMods()
        .map(
          (mod) => mod.copyWith(
            category: categories[mod.name],
            enabled: installer.isEnabled(mod),
          ),
        )
        .toList();
  }

  /// Categories currently in use, sorted for stable display.
  List<String> listCategories() {
    final categories = config.nteModCategories.values.toSet().toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  /// Turns a single mod on or off, applying the change immediately.
  Future<NteApplyResult> setEnabled(String modName, bool enabled) async {
    final mod = _resolve(modName);
    if (mod == null) {
      return NteApplyResult(errors: {modName: 'Mod is no longer in the library'});
    }

    final intent = config.nteEnabledMods.toSet();
    enabled ? intent.add(modName) : intent.remove(modName);
    await config.setNteEnabledMods(intent.toList());

    return installer.apply([mod], enabled ? {modName} : const {});
  }

  /// Reapplies stored intent, picking up any mod that was locked earlier.
  NteApplyResult syncWithIntent() {
    final intent = config.nteEnabledMods.toSet();
    return installer.apply(listMods(), intent);
  }

  /// Moves a mod into [category], or to the root when null. The mod is
  /// reinstalled so the game folder matches its new grouping.
  Future<NteApplyResult> setCategory(String modName, String? category) async {
    await config.setNteModCategory(modName, category);

    final mod = _resolve(modName);
    if (mod == null || !installer.isEnabled(mod)) return const NteApplyResult();

    try {
      installer.enable(mod);
      return NteApplyResult(applied: [modName]);
    } catch (e) {
      return NteModInstaller.isLockedError(e)
          ? NteApplyResult(locked: [modName])
          : NteApplyResult(errors: {modName: e.toString()});
    }
  }

  /// Imports mod folders and zip archives into the library.
  ///
  /// Returns the imported mods; [skipped] collects sources that held no
  /// installable files or already existed, with the reason.
  List<NteMod> import(List<String> paths, {required Map<String, String> skipped}) {
    final imported = <NteMod>[];

    for (final path in paths) {
      try {
        final NteMod? mod;

        if (FileSystemEntity.isDirectorySync(path)) {
          mod = library.importDirectory(path);
        } else if (NteModLibrary.isSupportedArchive(path)) {
          mod = library.importArchive(path);
        } else {
          skipped[p.basename(path)] = 'Unsupported file type';
          continue;
        }

        if (mod == null) {
          skipped[p.basename(path)] = 'No .pak or .asi files found';
        } else {
          imported.add(mod);
        }
      } catch (e) {
        skipped[p.basename(path)] = e is StateError ? e.message : e.toString();
      }
    }

    return imported;
  }

  /// Removes a mod from the game folder and then from the library.
  Future<void> delete(String modName) async {
    final mod = _resolve(modName);
    if (mod != null) {
      try {
        installer.disable(mod);
      } catch (_) {
        // The library copy is removed regardless; a locked game file is
        // cleaned up by the next sync.
      }
    }

    library.deleteMod(modName);
    await config.setNteModCategory(modName, null);

    final intent = config.nteEnabledMods..remove(modName);
    await config.setNteEnabledMods(intent);
  }

  NteMod? _resolve(String modName) {
    final mod = library.findMod(modName);
    return mod?.copyWith(category: config.nteModCategories[modName]);
  }
}
