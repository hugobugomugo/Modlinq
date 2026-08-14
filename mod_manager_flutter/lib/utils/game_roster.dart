import '../models/game_type.dart';
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
  };

  String iconPathFor(String characterId) => '$assetFolder/$characterId.png';

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
