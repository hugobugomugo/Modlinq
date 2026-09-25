import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/games/deadlock/deadlock_gameinfo.dart';
import 'package:modlinq/games/deadlock/deadlock_manager.dart';
import 'package:modlinq/services/config_service.dart';

const _vanillaGameinfo = '''
"GameInfo"
{
	FileSystem
	{
		SearchPaths
		{
			Game				citadel
		}
	}
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String gameRoot;
  late String libraryRoot;
  late ConfigService config;
  late DeadlockModManager manager;

  String addonsDir() => p.join(gameRoot, 'game', 'citadel', 'addons');
  String gameinfoPath() => p.join(gameRoot, 'game', 'citadel', 'gameinfo.gi');

  void addLibraryMod(String name, List<String> files) {
    final dir = Directory(p.join(libraryRoot, name))..createSync(recursive: true);
    for (final file in files) {
      File(p.join(dir.path, file)).writeAsStringSync(file);
    }
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('deadlock_mgr_');
    gameRoot = p.join(tmp.path, 'Deadlock');
    libraryRoot = p.join(tmp.path, 'library');

    File(gameinfoPath())
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(_vanillaGameinfo);

    config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
    await config.setDeadlockGamePath(gameRoot);
    await config.setDeadlockLibraryPath(libraryRoot);

    manager = DeadlockModManager.fromConfig(config)!;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('lists library mods with their installed state', () async {
    addLibraryMod('Skin', ['skin_dir.vpk']);

    expect(manager.listMods().single.name, 'Skin');
    expect(manager.listMods().single.enabled, isFalse);

    await manager.setEnabled('Skin', true);

    expect(manager.listMods().single.enabled, isTrue);
  });

  test('enabling the first mod patches gameinfo.gi', () async {
    addLibraryMod('Skin', ['skin_dir.vpk']);
    expect(DeadlockGameinfo(gameRoot).isPatched, isFalse);

    await manager.setEnabled('Skin', true);

    expect(DeadlockGameinfo(gameRoot).isPatched, isTrue);
    expect(File(p.join(addonsDir(), 'pak01_dir.vpk')).existsSync(), isTrue);
  });

  test('a game update that reset gameinfo.gi is repaired on the next enable',
      () async {
    addLibraryMod('A', ['a_dir.vpk']);
    addLibraryMod('B', ['b_dir.vpk']);
    await manager.setEnabled('A', true);

    File(gameinfoPath()).writeAsStringSync(_vanillaGameinfo);

    await manager.setEnabled('B', true);

    expect(DeadlockGameinfo(gameRoot).isPatched, isTrue);
  });

  test('a gameinfo.gi a patch reset is repaired on the next load', () async {
    addLibraryMod('A', ['a_dir.vpk']);
    await manager.setEnabled('A', true);

    File(gameinfoPath()).writeAsStringSync(_vanillaGameinfo);

    final result = await manager.syncWithIntent();

    expect(DeadlockGameinfo(gameRoot).isPatched, isTrue);
    expect(result.loaderRepaired, isTrue);
  });

  test('an intact gameinfo.gi is not reported as repaired', () async {
    addLibraryMod('A', ['a_dir.vpk']);
    await manager.setEnabled('A', true);

    expect((await manager.syncWithIntent()).loaderRepaired, isFalse);
  });

  test('repairs can be triggered without touching any mod', () async {
    addLibraryMod('A', ['a_dir.vpk']);
    await manager.setEnabled('A', true);
    File(gameinfoPath()).writeAsStringSync(_vanillaGameinfo);

    expect(await manager.repairGameinfo(), isTrue);
    expect(await manager.repairGameinfo(), isFalse);
  });

  test('slots survive a restart because they live in the config', () async {
    addLibraryMod('A', ['a_dir.vpk']);
    addLibraryMod('B', ['b_dir.vpk']);
    await manager.setEnabled('A', true);
    await manager.setEnabled('B', true);

    final restarted = DeadlockModManager.fromConfig(config)!;

    expect(restarted.slotOf('B'), 2);
    expect(restarted.listMods().where((m) => m.enabled).length, 2);
  });

  test('load order can be changed and is persisted', () async {
    addLibraryMod('A', ['a_dir.vpk']);
    addLibraryMod('B', ['b_dir.vpk']);
    await manager.setEnabled('A', true);
    await manager.setEnabled('B', true);

    await manager.setSlot('B', 1);

    expect(config.deadlockSlots['B'], 1);
    expect(config.deadlockSlots['A'], 2);
  });

  test('disabling removes the files and frees the slot', () async {
    addLibraryMod('A', ['a_dir.vpk']);
    await manager.setEnabled('A', true);

    await manager.setEnabled('A', false);

    expect(Directory(addonsDir()).listSync(), isEmpty);
    expect(config.deadlockSlots.containsKey('A'), isFalse);
  });

  test('no manager without a configured game folder', () async {
    SharedPreferences.setMockInitialValues({});
    final empty = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );

    expect(DeadlockModManager.fromConfig(empty), isNull);
  });
}
