import '../models/character_info.dart';
import '../models/nte_mod.dart';
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

  /// Category shown for mods the user has not grouped yet.
  static const String uncategorizedId = 'uncategorized';

  /// The library as [ModInfo], ready for the mod grid.
  List<ModInfo> listMods() {
    return manager.listMods().map(_toModInfo).toList();
  }

  ModInfo _toModInfo(NteMod mod) => ModInfo(
    id: mod.name,
    name: mod.name,
    characterId: mod.category ?? uncategorizedId,
    isActive: mod.enabled,
    imagePath: manager.previewImageFor(mod.name),
    isFavorite: manager.isFavorite(mod.name),
  );

  /// Category buckets for the strip above the grid, sorted by name with
  /// ungrouped mods last.
  List<CharacterInfo> buildCategories(List<ModInfo> mods, {required String uncategorizedLabel}) {
    final grouped = <String, List<ModInfo>>{};
    for (final mod in mods) {
      grouped.putIfAbsent(mod.characterId, () => []).add(mod);
    }

    final named = grouped.keys.where((id) => id != uncategorizedId).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return [
      for (final category in named)
        CharacterInfo(id: category, name: category, skins: grouped[category]!),
      if (grouped.containsKey(uncategorizedId))
        CharacterInfo(
          id: uncategorizedId,
          name: uncategorizedLabel,
          skins: grouped[uncategorizedId]!,
        ),
    ];
  }

  Future<NteApplyResult> toggle(ModInfo mod) =>
      manager.setEnabled(mod.id, !mod.isActive);

  Future<void> delete(ModInfo mod) => manager.delete(mod.id);

  Future<NteMod> rename(ModInfo mod, String newName) => manager.rename(mod.id, newName);

  Future<void> toggleFavorite(ModInfo mod) => manager.toggleFavorite(mod.id);

  void setImage(ModInfo mod, List<int> bytes, {String extension = 'png'}) =>
      manager.setPreviewImage(mod.id, bytes, extension: extension);

  /// Moves a mod into a category. [uncategorizedId] clears the grouping.
  Future<NteApplyResult> setCategory(ModInfo mod, String categoryId) =>
      manager.setCategory(mod.id, categoryId == uncategorizedId ? null : categoryId);
}
