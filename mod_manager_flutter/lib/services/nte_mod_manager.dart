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

  /// Installs mods that should be enabled but are not, such as one the game
  /// had locked when it was toggled.
  ///
  /// This never uninstalls. Mods already present in the game folder are adopted
  /// into the stored intent, so mods enabled before this app managed them — or
  /// by any other tool — are kept rather than removed.
  Future<NteApplyResult> syncWithIntent() async {
    final mods = listMods();
    final installed = mods.where((mod) => mod.enabled).map((mod) => mod.name).toSet();
    final intent = config.nteEnabledMods.toSet();

    final adopted = {...intent, ...installed};
    if (adopted.length != intent.length) {
      await config.setNteEnabledMods(adopted.toList());
    }

    final missing = mods.where((mod) => adopted.contains(mod.name) && !mod.enabled);
    if (missing.isEmpty) return const NteApplyResult();

    return installer.apply(missing, adopted);
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

  /// Renames a mod, carrying its category, enabled state and favourite flag
  /// across to the new name.
  ///
  /// An enabled mod is uninstalled first, because the copy in the game folder
  /// is keyed by the old name and would otherwise be left behind.
  Future<NteMod> rename(String oldName, String newName) async {
    final existing = _resolve(oldName);
    if (existing == null) {
      throw StateError('Mod "$oldName" is not in the library');
    }

    final wasEnabled = installer.isEnabled(existing);
    if (wasEnabled) installer.disable(existing);

    final renamed = library.renameMod(oldName, newName);

    final category = config.nteModCategories[oldName];
    if (category != null) {
      await config.setNteModCategory(oldName, null);
      await config.setNteModCategory(renamed.name, category);
    }

    final intent = config.nteEnabledMods.toSet();
    if (intent.remove(oldName)) intent.add(renamed.name);
    await config.setNteEnabledMods(intent.toList());

    final favorites = config.nteFavoriteMods.toSet();
    if (favorites.remove(oldName)) favorites.add(renamed.name);
    await config.setNteFavoriteMods(favorites.toList());

    final withCategory = renamed.copyWith(category: category);
    if (wasEnabled) installer.enable(withCategory);

    return withCategory.copyWith(enabled: wasEnabled);
  }

  bool isFavorite(String modName) => config.nteFavoriteMods.contains(modName);

  Future<void> toggleFavorite(String modName) async {
    final favorites = config.nteFavoriteMods.toSet();
    favorites.contains(modName) ? favorites.remove(modName) : favorites.add(modName);
    await config.setNteFavoriteMods(favorites.toList());
  }

  /// Stores a preview image for a mod and returns its path.
  String setPreviewImage(String modName, List<int> bytes, {String extension = 'png'}) =>
      library.setPreviewImage(modName, bytes, extension: extension);

  String? previewImageFor(String modName) => library.previewImageFor(modName);

  bool clearPreviewImage(String modName) => library.clearPreviewImage(modName);

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

    final favorites = config.nteFavoriteMods..remove(modName);
    await config.setNteFavoriteMods(favorites);
  }

  NteMod? _resolve(String modName) {
    final mod = library.findMod(modName);
    return mod?.copyWith(category: config.nteModCategories[modName]);
  }
}
