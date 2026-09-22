import 'package:path/path.dart' as p;

import 'dart:io';

import '../../models/game_type.dart';
import '../../models/nte_mod.dart';
import '../../services/config_service.dart';
import '../../services/nte_mod_library.dart';
import '../../services/nte_mods_adapter.dart';
import '../../utils/path_helper.dart';
import 'deadlock_gameinfo.dart';
import 'deadlock_installer.dart';

/// Slot store backed by the app config, so load order survives a restart.
class ConfigSlotStore implements DeadlockSlotStore {
  final ConfigService config;

  ConfigSlotStore(this.config);

  @override
  Map<String, int> get slots => config.deadlockSlots;

  @override
  Future<void> save(Map<String, int> value) => config.setDeadlockSlots(value);
}

/// Ties the Deadlock library, the game folder and the config together.
///
/// Mirrors [NteModManager]: the game folder is derived state, the library is
/// the source of truth, and nothing the user imported is ever deleted by
/// toggling a mod off.
class DeadlockModManager implements FileModManager {
  @override
  final NteModLibrary library;
  final DeadlockModInstaller installer;
  final DeadlockGameinfo gameinfo;
  final ConfigService config;

  DeadlockModManager({
    required this.library,
    required this.installer,
    required this.gameinfo,
    required this.config,
  });

  /// Source 2 archives. The rest of the library machinery - importing,
  /// previews, renaming - is shared with the other games.
  static const Set<String> payloadExtensions = {'vpk'};

  static DeadlockModManager? fromConfig(ConfigService config) {
    final gamePath = config.deadlockGamePath;
    if (gamePath == null || gamePath.isEmpty) return null;

    return DeadlockModManager(
      library: NteModLibrary(
        resolveLibraryPath(config),
        payloadExtensions: payloadExtensions,
      ),
      installer: DeadlockModInstaller(
        gameRoot: gamePath,
        slots: ConfigSlotStore(config),
      ),
      gameinfo: DeadlockGameinfo(gamePath),
      config: config,
    );
  }

  /// Imported mods live in the app data folder so they survive a game
  /// reinstall, same as the NTE library.
  static String resolveLibraryPath(ConfigService config) {
    final configured = config.deadlockLibraryPath;
    if (configured != null && configured.isNotEmpty) return configured;

    return p.join(PathHelper.getAppDataPath(), 'deadlock_mods');
  }

  @override
  GameType get gameType => GameType.deadlock;

  /// All library mods, with their category and live installed state.
  @override
  List<NteMod> listMods() {
    final categories = config.deadlockModCategories;

    return library
        .listMods()
        .map(
          (mod) => mod.copyWith(
            category: categories[mod.name],
            enabled: installer.isEnabled(mod.name),
          ),
        )
        .toList();
  }

  /// Installs mods that should be on but are not — a locked file, or a game
  /// folder wiped by an update. Never uninstalls, same rule as NTE.
  @override
  Future<NteApplyResult> syncWithIntent() async {
    final missing = listMods()
        .where((mod) => installer.slotOf(mod.name) != null && !mod.enabled)
        .toList();
    if (missing.isEmpty) return const NteApplyResult();

    final applied = <String>[];
    final errors = <String, String>{};

    gameinfo.ensurePatched();
    for (final mod in missing) {
      try {
        await installer.enable(mod.name, mod.dirPath);
        applied.add(mod.name);
      } catch (e) {
        errors[mod.name] = '$e';
      }
    }

    return NteApplyResult(applied: applied, errors: errors);
  }

  /// Copies folders and archives into the library.
  @override
  Future<List<NteMod>> import(
    List<String> paths, {
    required Map<String, String> skipped,
  }) async {
    final imported = <NteMod>[];

    for (final path in paths) {
      try {
        final NteMod? mod;

        if (FileSystemEntity.isDirectorySync(path)) {
          mod = library.importDirectory(path);
        } else if (NteModLibrary.isSupportedArchive(path)) {
          mod = await library.importArchive(path);
        } else {
          skipped[p.basename(path)] = 'Unsupported file type';
          continue;
        }

        if (mod == null) {
          skipped[p.basename(path)] = 'No .vpk files found';
        } else {
          imported.add(mod);
        }
      } catch (e) {
        skipped[p.basename(path)] = e is StateError ? e.message : e.toString();
      }
    }

    return imported;
  }

  List<String> listCategories() {
    final categories = config.deadlockModCategories.values.toSet().toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return categories;
  }

  /// Which `pakNN` slot a mod occupies, which is also its load order.
  int? slotOf(String modName) => installer.slotOf(modName);

  /// Turns a mod on or off.
  ///
  /// Enabling patches `gameinfo.gi` first: without that entry Source 2 never
  /// reads the addons folder, so the copy would look successful and change
  /// nothing in game.
  @override
  Future<NteApplyResult> setEnabled(String modName, bool enabled) async {
    if (!enabled) {
      await installer.disable(modName);
      return NteApplyResult(applied: [modName]);
    }

    final mod = library.findMod(modName);
    if (mod == null) {
      return NteApplyResult(
        errors: {modName: 'Mod is no longer in the library'},
      );
    }

    try {
      // Without the addons search path the copy succeeds and the game still
      // loads nothing, so the patch comes first.
      gameinfo.ensurePatched();
      await installer.enable(modName, mod.dirPath);

      return NteApplyResult(applied: [modName]);
    } catch (e) {
      return NteApplyResult(errors: {modName: '$e'});
    }
  }

  /// Puts the addons entry back after a game update dropped it.
  ///
  /// Returns whether anything had to be repaired, so the UI can say why the
  /// mods were gone.
  Future<bool> repairGameinfo() async => gameinfo.ensurePatched();

  /// Moves a mod to another load-order slot, swapping with whoever is there.
  Future<void> setSlot(String modName, int slot) =>
      installer.setSlot(modName, slot);

  @override
  Future<NteApplyResult> setCategory(String modName, String? category) async {
    await config.setDeadlockModCategory(modName, category);
    return const NteApplyResult();
  }

  @override
  String? previewImageFor(String modName) => library.previewImageFor(modName);

  @override
  String setPreviewImage(
    String modName,
    List<int> bytes, {
    String extension = 'png',
  }) => library.setPreviewImage(modName, bytes, extension: extension);

  @override
  bool clearPreviewImage(String modName) => library.clearPreviewImage(modName);

  @override
  bool isFavorite(String modName) =>
      config.deadlockFavoriteMods.contains(modName);

  @override
  Future<void> toggleFavorite(String modName) async {
    final favorites = config.deadlockFavoriteMods.toSet();
    favorites.contains(modName)
        ? favorites.remove(modName)
        : favorites.add(modName);

    await config.setDeadlockFavoriteMods(favorites.toList());
  }

  /// Uninstalls the mod, then drops it from the library and the config.
  @override
  Future<void> delete(String modName) async {
    await installer.disable(modName);
    library.deleteMod(modName);

    await config.setDeadlockModCategory(modName, null);
    await config.setDeadlockFavoriteMods(
      config.deadlockFavoriteMods.where((name) => name != modName).toList(),
    );
  }

  /// Renames a mod, carrying its slot, category and favourite flag across.
  ///
  /// An installed mod is uninstalled first: its files in the game folder are
  /// named after its slot, and the slot is keyed by the old name.
  @override
  Future<NteMod> rename(String oldName, String newName) async {
    final wasEnabled = installer.isEnabled(oldName);
    if (wasEnabled) await installer.disable(oldName);

    final renamed = library.renameMod(oldName, newName);

    final category = config.deadlockModCategories[oldName];
    if (category != null) {
      await config.setDeadlockModCategory(oldName, null);
      await config.setDeadlockModCategory(renamed.name, category);
    }

    final favorites = config.deadlockFavoriteMods.toSet();
    if (favorites.remove(oldName)) {
      favorites.add(renamed.name);
      await config.setDeadlockFavoriteMods(favorites.toList());
    }

    if (wasEnabled) await setEnabled(renamed.name, true);

    return renamed.copyWith(category: category);
  }
}
