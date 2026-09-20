import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/bundled_files.dart';
import 'package:modlinq/services/nte_game_detection.dart';
import 'package:modlinq/services/nte_loader_installer.dart';

void _writeFile(String path, [String content = 'x']) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsStringSync(content);
}

void main() {
  late Directory tmp;
  late String assetRoot;
  late String gameRoot;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nte_loader_');
    assetRoot = p.join(tmp.path, 'assets');
    gameRoot = p.join(tmp.path, 'game');

    _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.asi'), 'asi');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/subloader.dll'), 'sub');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.dll'), 'proxy');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  NteLoaderInstaller installerFor(NteEdition edition) => NteLoaderInstaller(
    gameRoot: gameRoot,
    edition: edition,
    source: DirectoryFileSource(assetRoot),
  );

  String win64(String name) => p.join(
    gameRoot,
    'Client',
    'WindowsNoEditor',
    'HT',
    'Binaries',
    'Win64',
    name,
  );

  group('proxy names', () {
    test('global and tw hook version.dll', () {
      expect(NteLoaderInstaller.proxyNamesFor(NteEdition.global), [
        'version.dll',
      ]);
      expect(NteLoaderInstaller.proxyNamesFor(NteEdition.tw), ['version.dll']);
    });

    test('cn hooks both sound and input dlls', () {
      expect(NteLoaderInstaller.proxyNamesFor(NteEdition.cn), [
        'dsound.dll',
        'dinput8.dll',
      ]);
    });
  });

  group('status', () {
    test('lists every missing file before install', () {
      final status = installerFor(NteEdition.global).status();

      expect(status.valid, isFalse);
      expect(status.missingFiles, [
        'loader.asi',
        'cutils.dll',
        'version.dll',
      ]);
    });

    test('is valid once all files are there', () async {
      await installerFor(NteEdition.global).install();

      final status = installerFor(NteEdition.global).status();
      expect(status.valid, isTrue);
      expect(status.missingFiles, isEmpty);
      expect(status.asiFound, isTrue);
      expect(status.cutilsFound, isTrue);
      expect(status.proxyFound, isTrue);
    });
  });

  group('install', () {
    test('copies the loader, renames subloader to cutils', () async {
      await installerFor(NteEdition.global).install();

      expect(File(win64('loader.asi')).readAsStringSync(), 'asi');
      expect(File(win64('cutils.dll')).readAsStringSync(), 'sub');
      expect(File(win64('version.dll')).readAsStringSync(), 'proxy');
    });

    test('cn gets both proxy dlls, global does not', () async {
      await installerFor(NteEdition.cn).install();

      expect(File(win64('dsound.dll')).existsSync(), isTrue);
      expect(File(win64('dinput8.dll')).existsSync(), isTrue);
      expect(File(win64('version.dll')).existsSync(), isFalse);
    });

    test('switching edition clears the other edition\'s proxy dll', () async {
      await installerFor(NteEdition.cn).install();
      await installerFor(NteEdition.global).install();

      expect(File(win64('version.dll')).existsSync(), isTrue);
      expect(File(win64('dsound.dll')).existsSync(), isFalse);
      expect(File(win64('dinput8.dll')).existsSync(), isFalse);
    });

    test('reinstalling identical files rewrites nothing', () async {
      await installerFor(NteEdition.global).install();
      final before = File(win64('loader.asi')).lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await installerFor(NteEdition.global).install();

      expect(File(win64('loader.asi')).lastModifiedSync(), before);
    });

    test('a changed bundled file replaces the installed one', () async {
      await installerFor(NteEdition.global).install();
      _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.asi'), 'asi v2');

      await installerFor(NteEdition.global).install();

      expect(File(win64('loader.asi')).readAsStringSync(), 'asi v2');
    });

    test('fails loudly when a bundled file is missing', () async {
      File(p.join(assetRoot, 'assets/nte_loader/loader.asi')).deleteSync();

      expect(
        () => installerFor(NteEdition.global).install(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('uninstall', () {
    test('removes loader files, plugins and every known proxy dll', () async {
      await installerFor(NteEdition.cn).install();
      _writeFile(win64('version.dll'), 'stale');
      _writeFile(win64('Anticensor.asi'), 'ac');
      _writeFile(win64('AyakaNTEModLoader.asi'), 'legacy');

      final status = installerFor(NteEdition.cn).uninstall();

      expect(status.valid, isFalse);
      for (final name in [
        'loader.asi',
        'cutils.dll',
        'version.dll',
        'dsound.dll',
        'dinput8.dll',
        'Anticensor.asi',
        'AyakaNTEModLoader.asi',
      ]) {
        expect(File(win64(name)).existsSync(), isFalse, reason: name);
      }
    });

    test('takes the log an asi plugin left behind with it', () async {
      await installerFor(NteEdition.global).install();
      _writeFile(win64('loader.log'), 'log');
      _writeFile(win64('Anticensor.asi'), 'ac');
      _writeFile(win64('Anticensor.log'), 'log');

      installerFor(NteEdition.global).uninstall();

      expect(File(win64('loader.log')).existsSync(), isFalse);
      expect(File(win64('Anticensor.log')).existsSync(), isFalse);
    });

    test('leaves unrelated files in the folder alone', () async {
      await installerFor(NteEdition.global).install();
      _writeFile(win64('HTGame.exe'), 'game');

      installerFor(NteEdition.global).uninstall();

      expect(File(win64('HTGame.exe')).existsSync(), isTrue);
    });
  });

  group('clean', () {
    test('wipes the mods folder and the named asi mods', () async {
      await installerFor(NteEdition.global).install();

      final paks = p.join(
        gameRoot,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Content',
        'Paks',
        '~mods',
      );
      _writeFile(p.join(paks, 'Skin', 'skin.pak'));
      _writeFile(win64('plugin.asi'), 'mod');
      _writeFile(win64('plugin.log'), 'log');

      installerFor(
        NteEdition.global,
      ).cleanGameMods(installedAsiNames: const ['plugin.asi']);

      expect(Directory(paks).existsSync(), isFalse);
      expect(File(win64('plugin.asi')).existsSync(), isFalse);
      expect(File(win64('plugin.log')).existsSync(), isFalse);
      expect(File(win64('loader.asi')).existsSync(), isFalse);
    });

    test('works on a folder that never had mods', () async {
      expect(
        () => installerFor(NteEdition.global).cleanGameMods(),
        returnsNormally,
      );
    });
  });
}
