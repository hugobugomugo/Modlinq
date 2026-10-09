import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/games/deadlock/deadlock_manager.dart';
import 'package:modlinq/services/config_service.dart';
import 'package:modlinq/utils/mod_name.dart';

/// A marketplace install names the mod after the store page, not after
/// whatever the uploader called the archive: GameBanana is full of
/// `compress_e587c.zip` and `pak01_dir.zip`, and the library key is the folder
/// name, so a bad name sticks to categories, favourites and slots as well.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String libraryRoot;
  late DeadlockModManager manager;

  /// An archive holding one `.vpk`, named the way uploaders name them.
  String makeArchive(String fileName) {
    final archive = Archive()
      ..addFile(ArchiveFile('pak83_dir.vpk', 4, [1, 2, 3, 4]));
    final path = p.join(tmp.path, fileName);
    File(path).writeAsBytesSync(ZipEncoder().encode(archive));
    return path;
  }

  String makeFolder(String folderName) {
    final dir = Directory(p.join(tmp.path, folderName))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'pak83_dir.vpk')).writeAsStringSync('vpk');
    return dir.path;
  }

  List<String> libraryNames() => Directory(libraryRoot)
      .listSync()
      .whereType<Directory>()
      .map((d) => p.basename(d.path))
      .toList()
    ..sort();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('import_naming_');
    libraryRoot = p.join(tmp.path, 'library');

    final gameRoot = p.join(tmp.path, 'Deadlock');
    File(p.join(gameRoot, 'game', 'citadel', 'gameinfo.gi'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('"GameInfo" {}');

    final config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
    await config.setDeadlockGamePath(gameRoot);
    await config.setDeadlockLibraryPath(libraryRoot);

    manager = DeadlockModManager.fromConfig(config)!;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('an archive is filed under the marketplace title', () async {
    final skipped = <String, String>{};

    final imported = await manager.import(
      [makeArchive('compress_e587c.zip')],
      skipped: skipped,
      nameOverride: ModName.sanitize('Baroness Mina'),
    );

    expect(imported.single.name, 'Baroness Mina');
    expect(libraryNames(), ['Baroness Mina']);
    expect(skipped, isEmpty);
  });

  test('a folder is filed under the marketplace title too', () async {
    final imported = await manager.import(
      [makeFolder('pak01_dir_59447')],
      skipped: <String, String>{},
      nameOverride: ModName.sanitize('Rice Shower Vindicta'),
    );

    expect(imported.single.name, 'Rice Shower Vindicta');
  });

  test('without a title the archive name is still used', () async {
    final imported = await manager.import(
      [makeArchive('compress_e587c.zip')],
      skipped: <String, String>{},
    );

    // A hand-dropped archive has no store page to take a name from.
    expect(imported.single.name, 'compress_e587c');
  });

  test('a second mod of the same title does not collide', () async {
    const title = 'Baroness Mina';

    await manager.import(
      [makeArchive('first.zip')],
      skipped: <String, String>{},
      nameOverride: title,
    );

    final taken = manager.listMods().map((mod) => mod.name).toSet();
    await manager.import(
      [makeArchive('second.zip')],
      skipped: <String, String>{},
      nameOverride: ModName.unique(title, taken),
    );

    expect(libraryNames(), ['Baroness Mina', 'Baroness Mina (2)']);
  });

  test('a batch keeps each source name, since one title cannot cover both', () async {
    final imported = await manager.import(
      [makeArchive('mod_one.zip'), makeArchive('mod_two.zip')],
      skipped: <String, String>{},
      nameOverride: 'Baroness Mina',
    );

    expect(imported.map((mod) => mod.name).toList(), ['mod_one', 'mod_two']);
  });
}
