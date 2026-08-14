import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mod_manager_flutter/services/config_service.dart';
import 'package:mod_manager_flutter/services/nte_mod_installer.dart';
import 'package:mod_manager_flutter/services/nte_mod_library.dart';
import 'package:mod_manager_flutter/services/nte_mod_manager.dart';

void _writeFile(String path) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsStringSync('x');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late NteModLibrary library;
  late NteModInstaller installer;
  late NteModManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('nte_sync_');
    library = NteModLibrary(p.join(tmp.path, 'library'));
    installer = NteModInstaller(p.join(tmp.path, 'game'));
    manager = NteModManager(
      library: library,
      installer: installer,
      config: ConfigService(await SharedPreferences.getInstance()),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void addMod(String name) => _writeFile(p.join(library.rootPath, name, '$name.pak'));

  test('adopts mods already installed instead of uninstalling them', () async {
    addMod('Preinstalled');
    installer.enable(library.findMod('Preinstalled')!);

    // Settings know nothing about it, as when a library is first imported.
    expect(manager.config.nteEnabledMods, isEmpty);

    await manager.syncWithIntent();

    expect(installer.isEnabled(library.findMod('Preinstalled')!), isTrue);
    expect(manager.config.nteEnabledMods, ['Preinstalled']);
  });

  test('installs a mod that intent wants but the game folder lacks', () async {
    addMod('Wanted');
    await manager.config.setNteEnabledMods(['Wanted']);

    final result = await manager.syncWithIntent();

    expect(result.applied, ['Wanted']);
    expect(installer.isEnabled(library.findMod('Wanted')!), isTrue);
  });

  test('never disables a mod, even when intent excludes it', () async {
    addMod('Untracked');
    installer.enable(library.findMod('Untracked')!);
    await manager.config.setNteEnabledMods(const []);

    await manager.syncWithIntent();

    expect(installer.isEnabled(library.findMod('Untracked')!), isTrue);
  });

  test('leaves a disabled mod alone when intent does not want it', () async {
    addMod('Idle');

    await manager.syncWithIntent();

    expect(installer.isEnabled(library.findMod('Idle')!), isFalse);
    expect(manager.config.nteEnabledMods, isEmpty);
  });

  test('disabling stays an explicit action', () async {
    addMod('Toggled');
    await manager.setEnabled('Toggled', true);
    expect(installer.isEnabled(library.findMod('Toggled')!), isTrue);

    await manager.setEnabled('Toggled', false);

    expect(installer.isEnabled(library.findMod('Toggled')!), isFalse);
    expect(manager.config.nteEnabledMods, isEmpty);

    // A later sync must not resurrect it.
    await manager.syncWithIntent();
    expect(installer.isEnabled(library.findMod('Toggled')!), isFalse);
  });
}
