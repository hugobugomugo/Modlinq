import '../models/game_type.dart';
import 'deadlock_characters.dart';
import 'mod_categories.dart';
import 'nte_characters.dart';
import 'ww_characters.dart';
import 'zzz_characters.dart';

/// The character roster for one game.
///
/// Every screen resolves characters through here, so a game can never show
/// another game's roster.
class GameRoster {
  final List<String> characterIds;
  final String assetFolder;
  final String Function(String id) displayNameOf;

  const GameRoster({
    required this.characterIds,
    required this.assetFolder,
    required this.displayNameOf,
  });

  static GameRoster of(GameType game) => switch (game) {
    GameType.zzz => GameRoster(
      characterIds: zzzCharacters,
      assetFolder: 'assets/characters',
      displayNameOf: getCharacterDisplayName,
    ),
    GameType.wutheringWaves => GameRoster(
      characterIds: wwCharacters,
      assetFolder: 'assets/characters_ww',
      displayNameOf: getWwCharacterDisplayName,
    ),
    GameType.nte => GameRoster(
      characterIds: nteCharacters,
      assetFolder: 'assets/characters_nte',
      displayNameOf: getNteCharacterDisplayName,
    ),
    GameType.deadlock => GameRoster(
      characterIds: deadlockCharacters,
      assetFolder: 'assets/characters_deadlock',
      displayNameOf: getDeadlockCharacterDisplayName,
    ),
  };

  String iconPathFor(String characterId) => '$assetFolder/$characterId.png';

  /// The roster id a human-readable [label] names, or null when it names
  /// nobody on this roster.
  ///
  /// GameBanana files a mod under a subcategory such as "Grey Talon", "Mo &
  /// Krill" or "Jane Doe"; this turns that into the id the library groups by.
  /// Matching ignores case, spacing and punctuation, so "Mo & Krill" and
  /// "mo_krill" both land on the same hero.
  String? idForLabel(String label) {
    final wanted = _squash(label);
    if (wanted.isEmpty) return null;

    for (final id in characterIds) {
      if (_squash(id) == wanted) return id;
      if (_squash(displayNameOf(id)) == wanted) return id;
    }

    return null;
  }

  static String _squash(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Roster plus the shared buckets, for pickers that must offer every
  /// destination a mod can be assigned to.
  List<String> get assignableIds => [
    ...characterIds,
    ModCategories.misc,
    ModCategories.unknown,
  ];

  /// Label for any assignable id, including the shared buckets.
  String labelFor(String id, {required String miscLabel, required String unknownLabel}) =>
      switch (id) {
        ModCategories.misc => miscLabel,
        ModCategories.unknown => unknownLabel,
        _ => displayNameOf(id),
      };
}
