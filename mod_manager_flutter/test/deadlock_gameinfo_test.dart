import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/games/deadlock/deadlock_gameinfo.dart';

const _vanilla = '''
"GameInfo"
{
	game 		"citadel"
	title 		"Citadel"

	FileSystem
	{
		// Shaped like the real Deadlock gameinfo.gi: no explicit Mod/Write keys,
		// so Source 2 derives MOD and DEFAULT_WRITE_PATH from the first Game path.
		SearchPaths
		{
			Game_UILanguage		citadel_*LANGUAGE*
			Game_LowViolence	citadel_lv
			Game				citadel
			Game				core
		}

		"UserSettingsPathID"		"USRLOCAL"
		"LegacyUserSettingsPathID"	"MOD"
	}
}
''';

/// A file that already pins the ids itself, e.g. patched by another manager.
const _pinned = '''
"GameInfo"
{
	FileSystem
	{
		SearchPaths
		{
			Game				citadel
			Mod					citadel
			Write				citadel
			Game				core
		}
	}
}
''';

void main() {
  late Directory tmp;
  late String gameRoot;
  late DeadlockGameinfo gameinfo;

  String gameinfoPath() =>
      p.join(gameRoot, 'game', 'citadel', 'gameinfo.gi');

  void writeVanilla([String content = _vanilla]) {
    final file = File(gameinfoPath());
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('deadlock_gi_');
    gameRoot = p.join(tmp.path, 'Deadlock');
    gameinfo = DeadlockGameinfo(gameRoot);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('patch', () {
    test('adds the addons search path above the base game path', () {
      writeVanilla();

      expect(gameinfo.isPatched, isFalse);
      gameinfo.patch();

      final lines = File(gameinfoPath()).readAsLinesSync();
      final addons = lines.indexWhere((l) => l.contains('citadel/addons'));
      final base = lines.indexWhere(
        (l) => RegExp(r'^\s*Game\s+citadel\s*$').hasMatch(l),
      );

      expect(addons, greaterThan(-1));
      expect(addons, lessThan(base));
      expect(gameinfo.isPatched, isTrue);
    });

    test('keeps the original around so the patch can be undone', () {
      writeVanilla();
      gameinfo.patch();

      expect(File('${gameinfoPath()}.modlinq.bak').existsSync(), isTrue);
    });

    test('patching twice does not add the line twice', () {
      writeVanilla();
      gameinfo.patch();
      gameinfo.patch();

      final hits = File(gameinfoPath())
          .readAsLinesSync()
          .where((l) => l.contains('citadel/addons'))
          .length;

      expect(hits, 1);
    });

    test('a game update that reverts the file is repaired', () {
      writeVanilla();
      gameinfo.patch();

      // what a Deadlock patch does: overwrite gameinfo.gi with the stock file
      writeVanilla();
      expect(gameinfo.isPatched, isFalse);

      expect(gameinfo.ensurePatched(), isTrue);
      expect(gameinfo.isPatched, isTrue);
    });

    test('ensurePatched does nothing when the line is already there', () {
      writeVanilla();
      gameinfo.patch();

      expect(gameinfo.ensurePatched(), isFalse);
    });

    test('a missing gameinfo.gi is reported, not silently created', () {
      expect(gameinfo.exists, isFalse);
      expect(() => gameinfo.patch(), throwsA(isA<StateError>()));
    });

    test('a file without a SearchPaths block is left alone', () {
      writeVanilla('"GameInfo"\n{\n\tgame "Deadlock"\n}\n');

      expect(() => gameinfo.patch(), throwsA(isA<StateError>()));
    });

    test('pins Mod and Write to citadel so keybindings keep resolving', () {
      writeVanilla();
      gameinfo.patch();

      final lines = File(gameinfoPath()).readAsLinesSync();
      final firstGame = lines.indexWhere(
        (l) => RegExp(r'^\s*Game\s+\S').hasMatch(l),
      );
      final mod = lines.indexWhere(
        (l) => RegExp(r'^\s*Mod\s+citadel\s*$').hasMatch(l),
      );
      final write = lines.indexWhere(
        (l) => RegExp(r'^\s*Write\s+citadel\s*$').hasMatch(l),
      );

      // Without these, MOD resolves to citadel/addons and the game aborts on
      // cfg/user_keys_default.vcfg: "Unable to read default keybinding
      // configuration".
      expect(lines[firstGame], contains('citadel/addons'));
      expect(mod, greaterThan(firstGame));
      expect(write, greaterThan(mod));
    });

    test('does not duplicate Mod/Write keys the file already has', () {
      writeVanilla(_pinned);
      gameinfo.patch();

      final lines = File(gameinfoPath()).readAsLinesSync();
      final mods = lines
          .where((l) => RegExp(r'^\s*Mod\s+citadel\s*$').hasMatch(l))
          .length;
      final writes = lines
          .where((l) => RegExp(r'^\s*Write\s+citadel\s*$').hasMatch(l))
          .length;

      expect(mods, 1);
      expect(writes, 1);
    });
  });

  group('unpatch', () {
    test('removes the addons line again', () {
      writeVanilla();
      gameinfo.patch();

      gameinfo.unpatch();

      expect(gameinfo.isPatched, isFalse);
      expect(
        File(gameinfoPath()).readAsStringSync().contains('citadel/addons'),
        isFalse,
      );
    });

    test('leaves the rest of the file byte for byte intact', () {
      writeVanilla();
      final before = File(gameinfoPath()).readAsStringSync();

      gameinfo.patch();
      gameinfo.unpatch();

      expect(File(gameinfoPath()).readAsStringSync(), before);
    });
  });
}
