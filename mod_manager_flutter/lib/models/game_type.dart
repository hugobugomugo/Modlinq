import '../games/game_registry.dart';

/// Games supported by the mod manager.
///
/// [zzz] and [wutheringWaves] are managed through 3dmigoto-style symlinked
/// mod folders. [nte] uses Unreal `.pak` / `.asi` files and is handled by a
/// different backend.
///
/// Labels and capabilities live in the game modules; this extension only
/// forwards, so nothing has to be kept in sync by hand.
enum GameType { zzz, wutheringWaves, nte, deadlock }

extension GameTypeX on GameType {
  /// Stable identifier used in config storage and on-disk paths.
  ///
  /// These values are persisted — do not rename them without a migration.
  String get key => switch (this) {
    GameType.zzz => 'zzz',
    GameType.wutheringWaves => 'ww',
    GameType.nte => 'nte',
    GameType.deadlock => 'deadlock',
  };

  /// Short label for the game switcher.
  String get shortLabel => GameRegistry.of(this).shortLabel;

  /// Full game name, used for tooltips.
  String get displayName => GameRegistry.of(this).displayName;

  /// Whether this game organises mods by character.
  ///
  /// NTE mods are grouped into user-defined categories instead.
  bool get hasCharacters => GameRegistry.of(this).caps.hasCharacters;

  /// Whether mods are applied as `.pak` / `.asi` files rather than symlinks.
  bool get usesPakMods => GameRegistry.of(this).caps.usesPakMods;

  static GameType fromKey(String? key) => switch (key) {
    'ww' => GameType.wutheringWaves,
    'nte' => GameType.nte,
    'deadlock' => GameType.deadlock,
    _ => GameType.zzz,
  };
}
