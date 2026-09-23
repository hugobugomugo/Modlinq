import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/game_type.dart';

/// Stores the icons a user picked for the game rail.
///
/// Deliberately outside the game folders: a game reinstall or a moved library
/// must not take the user's icon with it. One file per game, named after the
/// config key, so the mapping needs no bookkeeping.
class GameIconStore {
  final String rootPath;

  GameIconStore(this.rootPath);

  static const List<String> supportedExtensions = ['png', 'jpg', 'jpeg', 'webp'];

  /// Prefix for artwork fetched from GameBanana, kept apart from the user's
  /// own so "reset icon" falls back to it instead of to a letter.
  ///
  /// Versioned: the first release cached 32x32 game icons, which looked awful
  /// on the tile. Bumping the prefix retires those without asking anyone to
  /// clear a cache.
  static const String autoPrefix = 'auto2_';

  static const String _legacyAutoPrefix = 'auto_';

  /// Path of [game]'s custom icon, or null when it still uses the bundled one.
  String? iconPathFor(GameType game) {
    for (final extension in supportedExtensions) {
      final candidate = p.join(rootPath, '${game.key}.$extension');
      if (File(candidate).existsSync()) return candidate;
    }

    return null;
  }

  bool hasCustomIcon(GameType game) => iconPathFor(game) != null;

  /// Icon fetched from the game's GameBanana page, if it was cached already.
  String? autoIconPathFor(GameType game) {
    final candidate = p.join(rootPath, '$autoPrefix${game.key}.png');
    return File(candidate).existsSync() ? candidate : null;
  }

  /// What the rail should draw: the user's icon wins, the fetched one is the
  /// fallback, and a letter tile is what is left when neither exists.
  String? effectiveIconPath(GameType game) =>
      iconPathFor(game) ?? autoIconPathFor(game);

  Future<String> saveAutoIcon(GameType game, List<int> bytes) async {
    final target = File(p.join(rootPath, '$autoPrefix${game.key}.png'));
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(bytes, flush: true);

    final legacy = File(p.join(rootPath, '$_legacyAutoPrefix${game.key}.png'));
    if (legacy.existsSync()) await legacy.delete();

    return target.path;
  }

  /// Writes a new icon, replacing any previous one regardless of its format.
  Future<String> setIcon(
    GameType game,
    List<int> bytes, {
    String extension = 'png',
  }) async {
    await clearIcon(game);

    final target = File(p.join(rootPath, '${game.key}.$extension'));
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(bytes, flush: true);

    return target.path;
  }

  /// Drops the custom icon so the bundled one shows again.
  Future<void> clearIcon(GameType game) async {
    for (final extension in supportedExtensions) {
      final file = File(p.join(rootPath, '${game.key}.$extension'));
      if (file.existsSync()) await file.delete();
    }
  }
}
