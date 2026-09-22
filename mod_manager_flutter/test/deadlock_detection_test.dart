import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/games/deadlock/deadlock_detection.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('deadlock_detect_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// Builds the parts of a Deadlock install the app relies on.
  String installAt(String name, {bool withGameinfo = true, bool withExe = true}) {
    final root = p.join(tmp.path, name);
    final citadel = Directory(p.join(root, 'game', 'citadel'))
      ..createSync(recursive: true);
    final bin = Directory(p.join(root, 'game', 'bin', 'win64'))
      ..createSync(recursive: true);

    if (withGameinfo) {
      File(p.join(citadel.path, 'gameinfo.gi')).writeAsStringSync('"GameInfo"');
    }
    if (withExe) {
      File(p.join(bin.path, 'deadlock.exe')).writeAsStringSync('');
    }

    return root;
  }

  group('validate', () {
    test('accepts a folder with gameinfo and the game binary', () {
      final install = DeadlockDetection.validate(installAt('Deadlock'));

      expect(install.valid, isTrue);
      expect(install.addonsPath, endsWith(p.join('citadel', 'addons')));
    });

    test('rejects a folder without gameinfo.gi', () {
      final install = DeadlockDetection.validate(
        installAt('Deadlock', withGameinfo: false),
      );

      expect(install.valid, isFalse);
    });

    test('rejects a folder without the game binary', () {
      final install = DeadlockDetection.validate(
        installAt('Deadlock', withExe: false),
      );

      expect(install.valid, isFalse);
    });

    test('rejects a path that does not exist', () {
      expect(DeadlockDetection.validate(p.join(tmp.path, 'nope')).valid, isFalse);
    });
  });

  group('autoDetect', () {
    test('finds the install inside a steam library', () {
      final steamRoot = p.join(tmp.path, 'Steam');
      final common = Directory(p.join(steamRoot, 'steamapps', 'common'))
        ..createSync(recursive: true);

      final game = p.join(common.path, 'Deadlock');
      Directory(game).createSync();
      Directory(p.join(game, 'game', 'citadel')).createSync(recursive: true);
      File(p.join(game, 'game', 'citadel', 'gameinfo.gi')).writeAsStringSync('x');
      Directory(p.join(game, 'game', 'bin', 'win64')).createSync(recursive: true);
      File(p.join(game, 'game', 'bin', 'win64', 'deadlock.exe'))
          .writeAsStringSync('');

      final install = DeadlockDetection.autoDetect(steamRoots: [steamRoot]);

      expect(install.valid, isTrue);
      expect(install.path, game);
    });

    test('reports nothing found when no library has it', () {
      final install = DeadlockDetection.autoDetect(steamRoots: [tmp.path]);

      expect(install.valid, isFalse);
      expect(install.path, isEmpty);
    });
  });
}
