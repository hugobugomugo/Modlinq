import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/services/bundled_files.dart';
import 'package:modlinq/services/config_service.dart';
import 'package:modlinq/services/nte_game_detection.dart';
import 'package:modlinq/services/nte_loader_service.dart';
import 'package:modlinq/services/nte_mod_installer.dart';
import 'package:modlinq/services/nte_mod_library.dart';
import 'package:modlinq/services/nte_mod_manager.dart';

void _writeFile(String path, [String content = 'x']) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsStringSync(content);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String gameRoot;
  late NteModLibrary library;
  late NteModManager manager;
  late NteLoaderService loaderService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nte_auto_loader_');
    gameRoot = p.join(tmp.path, 'game');

    final assetRoot = p.join(tmp.path, 'assets');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.asi'), 'asi');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/subloader.dll'), 'sub');
    _writeFile(p.join(assetRoot, 'assets/nte_loader/loader.dll'), 'proxy');

    library = NteModLibrary(p.join(tmp.path, 'library'));
    loaderService = NteLoaderService(
      gameRoot: gameRoot,
      edition: NteEdition.global,
      source: DirectoryFileSource(assetRoot),
    );

    manager = NteModManager(
      library: library,
      installer: NteModInstaller(gameRoot),
      config: ConfigService(
        await SharedPreferences.getInstance(),
        configDirectory: tmp.path,
      ),
      loader: loaderService,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void addMod(String name) =>
      _writeFile(p.join(library.rootPath, name, '$name.pak'));

  test('enabling the first mod installs the loader', () async {
    addMod('Skin');
    expect(loaderService.status.valid, isFalse);

    final result = await manager.setEnabled('Skin', true);

    expect(result.errors, isEmpty);
    expect(loaderService.status.valid, isTrue);
  });

  test('disabling a mod never touches the loader', () async {
    addMod('Skin');
    await manager.setEnabled('Skin', true);
    loaderService.installer.uninstall();

    await manager.setEnabled('Skin', false);

    expect(loaderService.status.valid, isFalse);
  });

  test('a repaired loader is left alone on the next enable', () async {
    addMod('Skin');
    await manager.setEnabled('Skin', true);

    final asi = File(
      p.join(loaderService.installer.loaderDir, 'loader.asi'),
    );
    final before = asi.lastModifiedSync();

    addMod('Other');
    await manager.setEnabled('Other', true);

    expect(asi.lastModifiedSync(), before);
  });

  test('syncWithIntent installs the loader before restoring mods', () async {
    addMod('Skin');
    await manager.setEnabled('Skin', true);
    loaderService.installer.uninstall();
    Directory(
      p.join(manager.installer.pakTarget, 'Skin'),
    ).deleteSync(recursive: true);

    final result = await manager.syncWithIntent();

    expect(result.applied, ['Skin']);
    expect(loaderService.status.valid, isTrue);
  });

  test('a loader a game update wiped is restored on the next load', () async {
    addMod('Skin');
    await manager.setEnabled('Skin', true);

    // What an NTE patch does: it replaces Binaries/Win64, so the loader is
    // gone while every mod file is still exactly where it was.
    loaderService.installer.uninstall();
    expect(loaderService.status.valid, isFalse);
    expect(manager.listMods().single.enabled, isTrue);

    final result = await manager.syncWithIntent();

    expect(loaderService.status.valid, isTrue);
    expect(result.loaderRepaired, isTrue);
    expect(result.errors, isEmpty);
  });

  test('a healthy loader is not reported as repaired', () async {
    addMod('Skin');
    await manager.setEnabled('Skin', true);

    final result = await manager.syncWithIntent();

    expect(result.loaderRepaired, isFalse);
  });

  test('a loader failure is reported without blocking the mod', () async {
    addMod('Skin');
    Directory(p.join(tmp.path, 'assets')).deleteSync(recursive: true);

    final result = await manager.setEnabled('Skin', true);

    expect(result.applied, ['Skin']);
    expect(result.errors[NteModManager.loaderResultKey], isNotNull);
  });
}
