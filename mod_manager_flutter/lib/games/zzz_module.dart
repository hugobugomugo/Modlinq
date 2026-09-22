import '../models/game_type.dart';
import 'game_module.dart';

class ZzzModule extends GameModule {
  const ZzzModule();

  @override
  GameType get type => GameType.zzz;

  @override
  String get shortLabel => 'ZZZ';

  @override
  String get displayName => 'Zenless Zone Zero';

  @override
  int get marketplaceGameId => 19567;

  @override
  GameCaps get caps => const GameCaps(hasCharacters: true, hasF10Reload: true);
}
