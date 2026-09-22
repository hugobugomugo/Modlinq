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

  /// Path of [game]'s custom icon, or null when it still uses the bundled one.
  String? iconPathFor(GameType game) {
    for (final extension in supportedExtensions) {
      final candidate = p.join(rootPath, '${game.key}.$extension');
      if (File(candidate).existsSync()) return candidate;
    }

    return null;
  }

  bool hasCustomIcon(GameType game) => iconPathFor(game) != null;

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
