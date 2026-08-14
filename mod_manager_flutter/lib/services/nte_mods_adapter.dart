import '../models/character_info.dart';
import '../models/nte_mod.dart';
import '../utils/mod_categories.dart';
import '../utils/nte_characters.dart';
import 'nte_mod_manager.dart';

/// Presents the NTE library through the same shapes the mods screen already
/// uses for ZZZ and Wuthering Waves.
///
/// The screen groups mods by character; NTE groups them by user-defined
/// category, so categories take the place of characters and the existing grid,
/// cards and context menu work unchanged.
class NteModsAdapter {
  final NteModManager manager;

  NteModsAdapter(this.manager);

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

    return [
      for (final id in ids)
        CharacterInfo(
          id: id,
          name: _labelFor(id),
          iconPath: 'assets/characters_nte/$id.png',
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

  /// Moves a mod into a category.
  ///
  /// Dropping onto unknown clears the assignment, which hands the mod back to
  /// name-based detection.
  Future<NteApplyResult> setCategory(ModInfo mod, String categoryId) => manager.setCategory(
    mod.id,
    categoryId == ModCategories.unknown ? null : categoryId,
  );
}
