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
  static const String basePath = 'citadel';
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

    final inserts = <String>[_pathLineLike(lines[anchor], 'Game', addonsPath)];

    // Source 2 derives the `MOD` and `DEFAULT_WRITE_PATH` ids from the *first*
    // `Game` search path whenever the file carries no explicit `Mod`/`Write`
    // key — and Deadlock's stock gameinfo.gi carries none. Putting addons on
    // top would hand both ids to `citadel/addons`, and since the 2026-10-03
    // build resolves `LegacyUserSettingsPathID` through `MOD`, the game dies
    // with "Unable to read default keybinding configuration" before the menu:
    // cfg/user_keys_default.vcfg only exists under `citadel`. Pin them.
    if (!lines.any(_isModPin)) {
      inserts.add(_pathLineLike(lines[anchor], 'Mod', basePath));
    }
    if (!lines.any(_isWritePin)) {
      inserts.add(_pathLineLike(lines[anchor], 'Write', basePath));
    }

    lines.insertAll(anchor, inserts);
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

  /// Removes the entry again, along with the `Mod`/`Write` pins that sit
  /// directly below it. The rest of the file is left as it is.
  void unpatch() {
    if (!exists) return;

    final file = File(path);
    final lines = file.readAsLinesSync();

    for (var i = lines.length - 1; i >= 0; i--) {
      if (!_isAddonsLine(lines[i])) continue;

      var end = i + 1;
      while (end < lines.length &&
          (_isModPin(lines[end]) || _isWritePin(lines[end]))) {
        end++;
      }
      lines.removeRange(i, end);
    }

    _write(file, lines);
  }

  /// Mirrors the anchor's indentation and spacing so the file keeps its shape.
  static String _pathLineLike(String anchor, String key, String value) {
    final indent = RegExp(r'^\s*').firstMatch(anchor)?.group(0) ?? '\t\t\t';
    final gap =
        RegExp(r'^\s*Game(\s+)').firstMatch(anchor)?.group(1) ?? '\t\t\t\t';

    return '$indent$key$gap$value';
  }

  static bool _isAddonsLine(String line) => line.contains(addonsPath);

  static bool _isBaseGameLine(String line) =>
      RegExp(r'^\s*Game\s+citadel\s*$').hasMatch(line);

  static bool _isModPin(String line) =>
      RegExp(r'^\s*Mod\s+citadel\s*$').hasMatch(line);

  static bool _isWritePin(String line) =>
      RegExp(r'^\s*Write\s+citadel\s*$').hasMatch(line);

  static void _write(File file, List<String> lines) =>
      file.writeAsStringSync('${lines.join('\n')}\n');
}
