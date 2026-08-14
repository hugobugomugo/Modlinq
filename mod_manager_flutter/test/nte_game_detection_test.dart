import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/nte_game_detection.dart';

/// Builds the shared game files every valid install must have.
void _writeSharedFiles(String root) {
  final win64 = Directory(p.join(root, 'Client', 'WindowsNoEditor', 'HT', 'Binaries', 'Win64'))
    ..createSync(recursive: true);
  final paks = Directory(p.join(root, 'Client', 'WindowsNoEditor', 'HT', 'Content', 'Paks'))
    ..createSync(recursive: true);

  File(p.join(win64.path, 'HTGame.exe')).writeAsStringSync('');
  File(p.join(paks.path, 'global.ucas')).writeAsStringSync('');
  File(p.join(paks.path, 'global.utoc')).writeAsStringSync('');
}

void _writeEdition(String root, String rootLauncher, String subfolder, List<String> binaries) {
  File(p.join(root, rootLauncher)).writeAsStringSync('');
  final dir = Directory(p.join(root, subfolder))..createSync(recursive: true);
  for (final exe in binaries) {
    File(p.join(dir.path, exe)).writeAsStringSync('');
  }
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('nte_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('validate', () {
    test('rejects a path that does not exist', () {
      final result = NteGameDetection.validate(p.join(tmp.path, 'nope'));
      expect(result.valid, isFalse);
      expect(result.edition, NteEdition.unknown);
    });

    test('rejects an empty path', () {
      expect(NteGameDetection.validate('').valid, isFalse);
    });

    test('rejects a folder missing the shared game files', () {
      _writeEdition(tmp.path, 'NTEGlobalLauncher.exe', 'NTEGlobal', [
        'NTEGlobalGame.exe',
        'NTEGlobalLauncher.exe',
        'NTEGlobalUpdate.exe',
      ]);
      expect(NteGameDetection.validate(tmp.path).valid, isFalse);
    });

    test('rejects shared files without any edition layout', () {
      _writeSharedFiles(tmp.path);
      final result = NteGameDetection.validate(tmp.path);
      expect(result.valid, isFalse);
      expect(result.edition, NteEdition.unknown);
    });

    test('detects the global edition', () {
      _writeSharedFiles(tmp.path);
      _writeEdition(tmp.path, 'NTEGlobalLauncher.exe', 'NTEGlobal', [
        'NTEGlobalGame.exe',
        'NTEGlobalLauncher.exe',
        'NTEGlobalUpdate.exe',
      ]);

      final result = NteGameDetection.validate(tmp.path);
      expect(result.valid, isTrue);
      expect(result.edition, NteEdition.global);
      expect(result.edition.launcherExe, 'NTEGlobalLauncher.exe');
    });

    test('detects the cn edition', () {
      _writeSharedFiles(tmp.path);
      _writeEdition(tmp.path, 'NTELauncher.exe', 'NTELauncher', [
        'NTEGame.exe',
        'NTELauncher.exe',
        'NTEUpdate.exe',
      ]);
      expect(NteGameDetection.validate(tmp.path).edition, NteEdition.cn);
    });

    test('detects the tw edition', () {
      _writeSharedFiles(tmp.path);
      _writeEdition(tmp.path, 'NTETWLauncher.exe', 'NTETW', [
        'NTETWGame.exe',
        'NTETWLauncher.exe',
        'NTETWUpdate.exe',
      ]);
      expect(NteGameDetection.validate(tmp.path).edition, NteEdition.tw);
    });

    test('rejects an edition with a missing binary', () {
      _writeSharedFiles(tmp.path);
      _writeEdition(tmp.path, 'NTEGlobalLauncher.exe', 'NTEGlobal', [
        'NTEGlobalGame.exe',
        'NTEGlobalLauncher.exe',
        // NTEGlobalUpdate.exe intentionally absent
      ]);
      expect(NteGameDetection.validate(tmp.path).valid, isFalse);
    });

    test('exposes the mod and binaries folders', () {
      _writeSharedFiles(tmp.path);
      _writeEdition(tmp.path, 'NTEGlobalLauncher.exe', 'NTEGlobal', [
        'NTEGlobalGame.exe',
        'NTEGlobalLauncher.exe',
        'NTEGlobalUpdate.exe',
      ]);

      final result = NteGameDetection.validate(tmp.path);
      expect(result.paksModsPath, endsWith(p.join('Content', 'Paks', '~mods')));
      expect(result.binariesPath, endsWith(p.join('Binaries', 'Win64')));
    });
  });

  group('vdfValue', () {
    test('reads a quoted value', () {
      expect(NteGameDetection.vdfValue('"path"\t\t"/mnt/games"', 'path'), '/mnt/games');
    });

    test('ignores a different key', () {
      expect(NteGameDetection.vdfValue('"label"\t\t"x"', 'path'), isNull);
    });

    test('ignores an unquoted value', () {
      expect(NteGameDetection.vdfValue('"path"\t\tbare', 'path'), isNull);
    });
  });

  group('findCompatPrefixFor', () {
    test('returns the prefix root for a path inside drive_c', () {
      final game = p.join(tmp.path, 'pfx', 'drive_c', 'Program Files', 'Neverness To Everness');
      expect(
        NteGameDetection.findCompatPrefixFor(game),
        p.join(tmp.path, 'pfx'),
      );
    });

    test('handles a game sitting directly in drive_c', () {
      final game = p.join(tmp.path, 'pfx', 'drive_c', 'NTE');
      expect(NteGameDetection.findCompatPrefixFor(game), p.join(tmp.path, 'pfx'));
    });

    test('returns null for a path with no prefix and no steam manifest', () {
      expect(NteGameDetection.findCompatPrefixFor(p.join(tmp.path, 'games', 'nte')), isNull);
    });
  });

  group('findSteamAppId', () {
    test('matches installdir case-insensitively and returns the appid', () {
      final steamapps = Directory(p.join(tmp.path, 'steamapps'))..createSync();
      File(p.join(steamapps.path, 'appmanifest_1234.acf')).writeAsStringSync(
        '"AppState"\n{\n"appid"\t\t"1234"\n"installdir"\t\t"Neverness To Everness"\n}\n',
      );

      expect(
        NteGameDetection.findSteamAppId(steamapps.path, 'neverness to everness'),
        '1234',
      );
    });

    test('returns null when no manifest matches', () {
      final steamapps = Directory(p.join(tmp.path, 'steamapps'))..createSync();
      File(p.join(steamapps.path, 'appmanifest_9.acf')).writeAsStringSync(
        '"appid"\t\t"9"\n"installdir"\t\t"Other Game"\n',
      );

      expect(NteGameDetection.findSteamAppId(steamapps.path, 'Neverness To Everness'), isNull);
    });

    test('returns null for a missing steamapps folder', () {
      expect(NteGameDetection.findSteamAppId(p.join(tmp.path, 'nope'), 'x'), isNull);
    });
  });
}
