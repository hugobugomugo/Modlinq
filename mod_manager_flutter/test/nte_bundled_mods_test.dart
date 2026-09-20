import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/bundled_files.dart';
import 'package:modlinq/services/nte_bundled_mods.dart';
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
  late NteLoaderInstaller loader;
  late NteBundledModsInstaller mods;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nte_bundled_');
    assetRoot = p.join(tmp.path, 'assets');
    gameRoot = p.join(tmp.path, 'game');

    _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.asi'), 'asi');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/subloader.dll'), 'sub');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.dll'), 'proxy');
    _writeFile(
      p.join(assetRoot, 'assets/nte_bundled/Anticensor/Anticensor.asi'),
      'anticensor',
    );
    for (final ext in ['pak', 'ucas', 'utoc']) {
      _writeFile(
        p.join(assetRoot, 'assets/nte_bundled/Hide_UID/Hide_UID_P.$ext'),
        ext,
      );
    }

    loader = NteLoaderInstaller(
      gameRoot: gameRoot,
      edition: NteEdition.global,
      source: DirectoryFileSource(assetRoot),
    );
    mods = NteBundledModsInstaller(
      gameRoot: gameRoot,
      source: DirectoryFileSource(assetRoot),
      loader: loader,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String win64(String name) => p.join(
    gameRoot,
    'Client',
    'WindowsNoEditor',
    'HT',
    'Binaries',
    'Win64',
    name,
  );

  String uiMod(String name) => p.join(
    gameRoot,
    'Client',
    'WindowsNoEditor',
    'HT',
    'Content',
    'Paks',
    '~mods',
    'UI',
    'Hide_UID',
    name,
  );

  group('anticensor', () {
    test('is refused while the loader is missing', () async {
      final status = await mods.setEnabled(NteBundledMod.anticensor, true);

      expect(status.installed, isFalse);
      expect(status.loaderInstalled, isFalse);
      expect(status.message, 'Install the loader first');
      expect(File(win64('Anticensor.asi')).existsSync(), isFalse);
    });

    test('a stale copy is cleared when the loader is gone', () async {
      _writeFile(win64('Anticensor.asi'), 'stale');
      _writeFile(win64('Anticensor.log'), 'log');

      await mods.setEnabled(NteBundledMod.anticensor, true);

      expect(File(win64('Anticensor.asi')).existsSync(), isFalse);
      expect(File(win64('Anticensor.log')).existsSync(), isFalse);
    });

    test('installs next to the loader once it is there', () async {
      await loader.install();

      final status = await mods.setEnabled(NteBundledMod.anticensor, true);

      expect(status.installed, isTrue);
      expect(status.loaderInstalled, isTrue);
      expect(File(win64('Anticensor.asi')).readAsStringSync(), 'anticensor');
    });

    test('disabling removes the plugin and its log', () async {
      await loader.install();
      await mods.setEnabled(NteBundledMod.anticensor, true);
      _writeFile(win64('Anticensor.log'), 'log');

      final status = await mods.setEnabled(NteBundledMod.anticensor, false);

      expect(status.installed, isFalse);
      expect(File(win64('Anticensor.asi')).existsSync(), isFalse);
      expect(File(win64('Anticensor.log')).existsSync(), isFalse);
    });

    test('reports an installed plugin the loader can no longer run', () async {
      await loader.install();
      await mods.setEnabled(NteBundledMod.anticensor, true);
      loader.uninstall();

      final status = mods.statusOf(NteBundledMod.anticensor);
      expect(status.installed, isFalse);
    });
  });

  group('hide uid', () {
    test('installs all three pak files without the loader', () async {
      final status = await mods.setEnabled(NteBundledMod.hideUid, true);

      expect(status.installed, isTrue);
      expect(File(uiMod('Hide_UID_P.pak')).readAsStringSync(), 'pak');
      expect(File(uiMod('Hide_UID_P.ucas')).existsSync(), isTrue);
      expect(File(uiMod('Hide_UID_P.utoc')).existsSync(), isTrue);
    });

    test('disabling removes the files and the empty folder', () async {
      await mods.setEnabled(NteBundledMod.hideUid, true);
      await mods.setEnabled(NteBundledMod.hideUid, false);

      expect(mods.isInstalled(NteBundledMod.hideUid), isFalse);
      expect(Directory(p.dirname(uiMod('Hide_UID_P.pak'))).existsSync(), isFalse);
    });
  });

  test('removeAll clears both extras', () async {
    await loader.install();
    await mods.setEnabled(NteBundledMod.anticensor, true);
    await mods.setEnabled(NteBundledMod.hideUid, true);

    mods.removeAll();

    expect(mods.isInstalled(NteBundledMod.anticensor), isFalse);
    expect(mods.isInstalled(NteBundledMod.hideUid), isFalse);
  });
}
