import '../models/game_type.dart';
import 'game_module.dart';

class WuwaModule extends GameModule {
  const WuwaModule();

  @override
  GameType get type => GameType.wutheringWaves;

  @override
  String get shortLabel => 'WW';

  @override
  String get displayName => 'Wuthering Waves';

  @override
  int get marketplaceGameId => 20357;

  @override
  GameCaps get caps => const GameCaps(hasCharacters: true);
}
