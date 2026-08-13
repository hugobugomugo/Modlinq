/// Games supported by the mod manager.
///
/// [zzz] and [wutheringWaves] are managed through 3dmigoto-style symlinked
/// mod folders. [nte] uses Unreal `.pak` / `.asi` files and is handled by a
/// different backend.
enum GameType { zzz, wutheringWaves, nte }

extension GameTypeX on GameType {
  /// Stable identifier used in config storage and on-disk paths.
  ///
  /// These values are persisted — do not rename them without a migration.
  String get key => switch (this) {
    GameType.zzz => 'zzz',
    GameType.wutheringWaves => 'ww',
    GameType.nte => 'nte',
  };

  /// Short label for the game switcher.
  String get shortLabel => switch (this) {
    GameType.zzz => 'ZZZ',
    GameType.wutheringWaves => 'WW',
    GameType.nte => 'NTE',
  };

  /// Full game name, used for tooltips.
  String get displayName => switch (this) {
    GameType.zzz => 'Zenless Zone Zero',
    GameType.wutheringWaves => 'Wuthering Waves',
    GameType.nte => 'Neverness to Everness',
  };

  /// Whether this game organises mods by character.
  ///
  /// NTE mods are grouped into user-defined categories instead.
  bool get hasCharacters => this != GameType.nte;

  /// Whether mods are applied as `.pak` / `.asi` files rather than symlinks.
  bool get usesPakMods => this == GameType.nte;

  static GameType fromKey(String? key) => switch (key) {
    'ww' => GameType.wutheringWaves,
    'nte' => GameType.nte,
    _ => GameType.zzz,
  };
}
