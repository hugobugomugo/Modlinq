import '../models/game_type.dart';
import '../services/config_service.dart';
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

  /// 3DMigoto needs both the mods folder it watches and the folder mods are
  /// stored in.
  @override
  bool isConfigured(ConfigService config) =>
      (config.zzzModsPath ?? '').isNotEmpty;
}
