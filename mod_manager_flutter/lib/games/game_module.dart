import '../models/game_type.dart';
import '../services/config_service.dart';

/// What a game can do, asked by the shared screens instead of checking which
/// game is selected.
///
/// A new game answers these questions once, in its own module, rather than
/// adding another branch to every screen.
class GameCaps {
  /// Mods are grouped by playable character, with a character grid on top.
  final bool hasCharacters;

  /// Mods are installed as files copied into the game (`.pak`, `.asi`, `.vpk`)
  /// rather than as 3DMigoto symlinks.
  final bool usesPakMods;

  /// The game reloads mods on F10 while running.
  final bool hasF10Reload;

  /// The game needs a loader or patched config before mods do anything.
  final bool needsLoader;

  const GameCaps({
    this.hasCharacters = false,
    this.usesPakMods = false,
    this.hasF10Reload = false,
    this.needsLoader = false,
  });
}

/// Everything the app needs to know about one supported game.
///
/// Adding a game means writing one of these and listing it in the registry;
/// no screen should ever name a game directly.
abstract class GameModule {
  const GameModule();

  /// Enum member this module backs. Kept while `GameType` is still the value
  /// persisted in the config.
  GameType get type;

  /// Stable key used in config storage and on-disk paths.
  String get key => type.key;

  /// Short label for the game switcher.
  String get shortLabel;

  /// Full game name, used in headers and tooltips.
  String get displayName;

  /// GameBanana hub id, which drives the marketplace for this game.
  int get marketplaceGameId;

  GameCaps get caps;

  /// Whether this game has the folders it needs to install anything.
  ///
  /// The marketplace asks before offering an install: downloading a mod for a
  /// game whose folder is unknown would end in an error after the download,
  /// which is the worst possible moment to find out.
  bool isConfigured(ConfigService config);

  String get marketplaceUrl => 'https://gamebanana.com/games/$marketplaceGameId';

  String marketplaceSearchUrl(String query) =>
      'https://gamebanana.com/search?_type=Mods&game=$marketplaceGameId'
      '&query=${Uri.encodeComponent(query)}';
}
