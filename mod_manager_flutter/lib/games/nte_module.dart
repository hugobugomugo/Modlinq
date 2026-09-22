import '../models/game_type.dart';
import 'game_module.dart';

class NteModule extends GameModule {
  const NteModule();

  @override
  GameType get type => GameType.nte;

  @override
  String get shortLabel => 'NTE';

  @override
  String get displayName => 'Neverness to Everness';

  @override
  int get marketplaceGameId => 23012;

  @override
  GameCaps get caps =>
      const GameCaps(usesPakMods: true, needsLoader: true);
}
