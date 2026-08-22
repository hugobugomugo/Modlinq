import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/services/config_service.dart';
import 'package:modlinq/services/nte_mod_installer.dart';
import 'package:modlinq/services/nte_mod_library.dart';
import 'package:modlinq/services/nte_mod_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late NteModLibrary library;
  late NteModInstaller installer;
  late ConfigService config;
  late NteModManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nte_autotag_');
    library = NteModLibrary(p.join(tmp.path, 'library'));
    installer = NteModInstaller(p.join(tmp.path, 'game'));
    config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
    manager = NteModManager(
      library: library,
      installer: installer,
      config: config,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void addMod(String name) {
    final file = File(p.join(library.rootPath, name, 'skin.pak'));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('pak');
  }

  test('tags mods with the character detected from their folder name', () async {
    addMod('mint_nurse');
    addMod('jiuyuan_maid_p');

    final tagged = await manager.autoTagAll();

    expect(tagged, {'mint_nurse': 'mint', 'jiuyuan_maid_p': 'jiuyuan'});
    expect(config.nteModCategories['mint_nurse'], 'mint');
  });

  test('leaves a mod whose name matches no character alone', () async {
    addMod('_____sfw_v132');

    final tagged = await manager.autoTagAll();

    expect(tagged, isEmpty);
    expect(config.nteModCategories.containsKey('_____sfw_v132'), isFalse);
  });

  test('never overwrites a category the user chose', () async {
    addMod('mint_nurse');
    await config.setNteModCategory('mint_nurse', 'misc');

    final tagged = await manager.autoTagAll();

    expect(tagged, isEmpty);
    expect(config.nteModCategories['mint_nurse'], 'misc');
  });

  test('does not move any installed files', () async {
    addMod('mint_nurse');
    final mod = library.findMod('mint_nurse')!;
    installer.enable(mod);
    final before = Directory(installer.gameRoot)
        .listSync(recursive: true)
        .map((e) => e.path)
        .toList()
      ..sort();

    await manager.autoTagAll();

    final after = Directory(installer.gameRoot)
        .listSync(recursive: true)
        .map((e) => e.path)
        .toList()
      ..sort();
    expect(after, before, reason: 'tagging must stay metadata only');
  });
}
