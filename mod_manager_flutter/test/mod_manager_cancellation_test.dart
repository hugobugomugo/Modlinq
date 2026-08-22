import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/services/config_service.dart';
import 'package:modlinq/services/mod_manager_service.dart';
import 'package:modlinq/utils/cancellation_token.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ProviderContainer container;
  late ModManagerService manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('mod_scan_');

    final modsPath = p.join(tmp.path, 'mods');
    final linksPath = p.join(tmp.path, 'links');
    Directory(modsPath).createSync(recursive: true);
    Directory(linksPath).createSync(recursive: true);

    // Must stay inside tmp: without it this writes the real user config.
    final config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
    await config.setZzzPaths(modsPath, linksPath);

    container = ProviderContainer();
    manager = ModManagerService(config, container);
  });

  tearDown(() {
    container.dispose();
    tmp.deleteSync(recursive: true);
  });

  void addMod(String name) {
    final dir = Directory(p.join(manager.modsPath!, name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'mod.ini')).writeAsStringSync('[Constants]');
  }

  test('returns every mod when nothing cancels the scan', () async {
    addMod('Alpha');
    addMod('Beta');
    addMod('Gamma');

    final mods = await manager.getModsInfo();

    expect(mods.map((m) => m.id), containsAll(['Alpha', 'Beta', 'Gamma']));
  });

  test('does no per-mod work once the token is cancelled', () async {
    addMod('Alpha');
    addMod('Beta');
    addMod('Gamma');

    final mods = await manager.getModsInfo(
      cancelled: CancellationToken()..cancel(),
    );

    expect(mods, isEmpty);
  });

  test('an uncancelled token behaves like no token at all', () async {
    addMod('Alpha');

    final mods = await manager.getModsInfo(cancelled: CancellationToken());

    expect(mods.map((m) => m.id), ['Alpha']);
  });
}
