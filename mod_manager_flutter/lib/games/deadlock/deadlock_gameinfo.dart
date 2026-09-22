import 'dart:io';

import 'package:path/path.dart' as p;

/// Manages the `SearchPaths` entry Deadlock needs before it loads any mod.
///
/// Source 2 only reads `citadel/addons` when `gameinfo.gi` lists it, and it
/// has to come before the stock `citadel` entry so modded files win. Game
/// updates ship a fresh `gameinfo.gi`, which silently drops every mod — that
/// is what [ensurePatched] exists for.
class DeadlockGameinfo {
  final String gameRoot;

  DeadlockGameinfo(this.gameRoot);

  static const String addonsPath = 'citadel/addons';
  static const String backupSuffix = '.modlinq.bak';

  String get path => p.join(gameRoot, 'game', 'citadel', 'gameinfo.gi');

  String get backupPath => '$path$backupSuffix';

  bool get exists => File(path).existsSync();

  /// Whether the addons entry is currently in the file.
  bool get isPatched {
    if (!exists) return false;
    return File(path).readAsLinesSync().any(_isAddonsLine);
  }

  /// Adds the addons entry, keeping a copy of the untouched file.
  void patch() {
    if (!exists) {
      throw StateError('gameinfo.gi not found at $path');
    }

    final file = File(path);
    final lines = file.readAsLinesSync();
    if (lines.any(_isAddonsLine)) return;

    final anchor = lines.indexWhere(_isBaseGameLine);
    if (anchor < 0) {
      throw StateError('gameinfo.gi has no "Game citadel" search path');
    }

    // Keep the original once, so unpatching cannot be confused by a game
    // update that rewrote everything else in the file.
    if (!File(backupPath).existsSync()) {
      file.copySync(backupPath);
    }

    lines.insert(anchor, _addonsLineLike(lines[anchor]));
    _write(file, lines);
  }

  /// Puts the entry back after a game update removed it.
  ///
  /// Returns whether anything had to be repaired, so callers can tell the user
  /// why their mods were gone.
  bool ensurePatched() {
    if (isPatched) return false;

    patch();
    return true;
  }

  /// Removes the entry again. The rest of the file is left as it is.
  void unpatch() {
    if (!exists) return;

    final file = File(path);
    final lines = file.readAsLinesSync()..removeWhere(_isAddonsLine);
    _write(file, lines);
  }

  /// Mirrors the anchor's indentation and spacing so the file keeps its shape.
  static String _addonsLineLike(String anchor) {
    final indent = RegExp(r'^\s*').firstMatch(anchor)?.group(0) ?? '\t\t\t';
    final gap =
        RegExp(r'^\s*Game(\s+)').firstMatch(anchor)?.group(1) ?? '\t\t\t\t';

    return '${indent}Game$gap$addonsPath';
  }

  static bool _isAddonsLine(String line) => line.contains(addonsPath);

  static bool _isBaseGameLine(String line) =>
      RegExp(r'^\s*Game\s+citadel\s*$').hasMatch(line);

  static void _write(File file, List<String> lines) =>
      file.writeAsStringSync('${lines.join('\n')}\n');
}
