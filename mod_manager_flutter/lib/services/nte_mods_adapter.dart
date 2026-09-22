import '../models/character_info.dart';
import '../models/game_type.dart';
import '../models/nte_mod.dart';
import '../utils/mod_categories.dart';
import '../utils/game_roster.dart';
import '../utils/nte_characters.dart';
import 'nte_mod_library.dart';

/// What the mods screen needs from a game whose mods are copied files rather
/// than 3DMigoto symlinks.
///
/// NTE and Deadlock differ in how files reach the game, not in how the user
/// works with them, so the grid talks to this and never to a specific game.
abstract class FileModManager {
  GameType get gameType;

  /// The app-managed folder the mods were imported into.
  NteModLibrary get library;

  List<NteMod> listMods();

  /// Installs whatever should be enabled but is not, without ever
  /// uninstalling. Run on load so a mod the game had locked is retried.
  Future<NteApplyResult> syncWithIntent();

  /// Copies folders and archives into the library. [skipped] collects sources
  /// that held nothing installable, with the reason.
  Future<List<NteMod>> import(
    List<String> paths, {
    required Map<String, String> skipped,
  });

  String? previewImageFor(String modName);

  bool isFavorite(String modName);

  Future<NteApplyResult> setEnabled(String modName, bool enabled);

  Future<NteApplyResult> setCategory(String modName, String? category);

  Future<void> delete(String modName);

  Future<NteMod> rename(String oldName, String newName);

  Future<void> toggleFavorite(String modName);

  String setPreviewImage(String modName, List<int> bytes, {String extension});

  bool clearPreviewImage(String modName);
}

/// Presents the NTE library through the same shapes the mods screen already
/// uses for ZZZ and Wuthering Waves.
///
/// The screen groups mods by character; NTE groups them by user-defined
/// category, so categories take the place of characters and the existing grid,
/// cards and context menu work unchanged.
class NteModsAdapter {
  final FileModManager manager;

  NteModsAdapter(this.manager);

  GameType get gameType => manager.gameType;

  /// The library as [ModInfo], ready for the mod grid.
  List<ModInfo> listMods() {
    return manager.listMods().map(_toModInfo).toList();
  }

  /// A mod's group: the category the user assigned, otherwise the character
  /// detected from its folder name, otherwise the unknown bucket.
  static String groupOf(NteMod mod) {
    final assigned = mod.category;
    if (assigned != null && assigned.isNotEmpty) return assigned;

    return detectNteCharacter(mod.name) ?? ModCategories.unknown;
  }

  ModInfo _toModInfo(NteMod mod) => ModInfo(
    id: mod.name,
    name: mod.name,
    characterId: groupOf(mod),
    isActive: mod.enabled,
    imagePath: manager.previewImageFor(mod.name),
    isFavorite: manager.isFavorite(mod.name),
  );

  /// Groups mods by character or user-defined category.
  ///
  /// The misc and unknown buckets are left out; the screen adds those for every
  /// game so they look and behave the same everywhere.
  List<CharacterInfo> buildCategories(List<ModInfo> mods) {
    final grouped = <String, List<ModInfo>>{};
    for (final mod in mods) {
      if (ModCategories.isSpecial(mod.characterId)) continue;
      grouped.putIfAbsent(mod.characterId, () => []).add(mod);
    }

    final ids = grouped.keys.toList()
      ..sort((a, b) => _labelFor(a).toLowerCase().compareTo(_labelFor(b).toLowerCase()));

    final roster = GameRoster.of(gameType);

    return [
      for (final id in ids)
        CharacterInfo(
          id: id,
          name: _labelFor(id),
          iconPath: roster.iconPathFor(id),
          skins: grouped[id]!,
        ),
    ];
  }

  /// Characters get their roster name; free-form categories keep theirs.
  static String _labelFor(String id) =>
      nteCharacters.contains(id) ? getNteCharacterDisplayName(id) : id;

  /// Mods grouped by the special buckets, for the screen to render.
  Map<String, List<ModInfo>> specialBuckets(List<ModInfo> mods) {
    final buckets = <String, List<ModInfo>>{};
    for (final mod in mods) {
      if (!ModCategories.isSpecial(mod.characterId)) continue;
      buckets.putIfAbsent(mod.characterId, () => []).add(mod);
    }
    return buckets;
  }

  Future<NteApplyResult> toggle(ModInfo mod) =>
      manager.setEnabled(mod.id, !mod.isActive);

  Future<void> delete(ModInfo mod) => manager.delete(mod.id);

  Future<NteMod> rename(ModInfo mod, String newName) => manager.rename(mod.id, newName);

  Future<void> toggleFavorite(ModInfo mod) => manager.toggleFavorite(mod.id);

  void setImage(ModInfo mod, List<int> bytes, {String extension = 'png'}) =>
      manager.setPreviewImage(mod.id, bytes, extension: extension);

  bool clearImage(ModInfo mod) => manager.clearPreviewImage(mod.id);

  /// Moves a mod into a category.
  ///
  /// Dropping onto unknown clears the assignment, which hands the mod back to
  /// name-based detection.
  Future<NteApplyResult> setCategory(ModInfo mod, String categoryId) => manager.setCategory(
    mod.id,
    categoryId == ModCategories.unknown ? null : categoryId,
  );
}
