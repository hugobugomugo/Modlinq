import '../../models/game_type.dart';
import '../game_module.dart';

class DeadlockModule extends GameModule {
  const DeadlockModule();

  @override
  GameType get type => GameType.deadlock;

  @override
  String get shortLabel => 'DL';

  @override
  String get displayName => 'Deadlock';

  @override
  int get marketplaceGameId => 20948;

  /// `.vpk` archives copied into `citadel/addons`, which the engine only reads
  /// after `gameinfo.gi` has been patched — hence [GameCaps.needsLoader].
  @override
  GameCaps get caps => const GameCaps(usesPakMods: true, needsLoader: true);
}
