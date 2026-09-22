import '../models/game_type.dart';
import 'game_module.dart';
import 'nte_module.dart';
import 'wuwa_module.dart';
import 'zzz_module.dart';

/// The list of supported games.
///
/// This is the only place that knows every game. Screens read modules from
/// here, so adding a game is one entry plus its module file.
class GameRegistry {
  const GameRegistry._();

  static const List<GameModule> modules = [
    ZzzModule(),
    WuwaModule(),
    NteModule(),
  ];

  static GameModule of(GameType type) =>
      modules.firstWhere((module) => module.type == type);

  static GameModule? byKey(String key) {
    for (final module in modules) {
      if (module.key == key) return module;
    }
    return null;
  }
}
