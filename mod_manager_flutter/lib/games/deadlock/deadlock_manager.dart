import 'package:path/path.dart' as p;

import '../../models/nte_mod.dart';
import '../../services/config_service.dart';
import '../../services/nte_mod_library.dart';
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
class DeadlockModManager {
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

  /// All library mods, with their category and live installed state.
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
  Future<void> setEnabled(String modName, bool enabled) async {
    if (!enabled) {
      await installer.disable(modName);
      return;
    }

    final mod = library.findMod(modName);
    if (mod == null) {
      throw StateError('Mod "$modName" is no longer in the library');
    }

    gameinfo.ensurePatched();
    await installer.enable(modName, mod.dirPath);
  }

  /// Puts the addons entry back after a game update dropped it.
  ///
  /// Returns whether anything had to be repaired, so the UI can say why the
  /// mods were gone.
  Future<bool> repairGameinfo() async => gameinfo.ensurePatched();

  /// Moves a mod to another load-order slot, swapping with whoever is there.
  Future<void> setSlot(String modName, int slot) =>
      installer.setSlot(modName, slot);

  Future<void> setCategory(String modName, String? category) =>
      config.setDeadlockModCategory(modName, category);
}
