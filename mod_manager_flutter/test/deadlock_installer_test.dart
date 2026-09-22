import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/games/deadlock/deadlock_installer.dart';

void main() {
  late Directory tmp;
  late String gameRoot;
  late String libraryRoot;
  late DeadlockModInstaller installer;

  String addonsDir() => p.join(gameRoot, 'game', 'citadel', 'addons');

  /// A library mod folder holding [files].
  String addLibraryMod(String name, List<String> files) {
    final dir = Directory(p.join(libraryRoot, name))..createSync(recursive: true);
    for (final file in files) {
      File(p.join(dir.path, file)).writeAsStringSync(file);
    }
    return dir.path;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('deadlock_mods_');
    gameRoot = p.join(tmp.path, 'Deadlock');
    libraryRoot = p.join(tmp.path, 'library');
    Directory(addonsDir()).createSync(recursive: true);
    installer = DeadlockModInstaller(
      gameRoot: gameRoot,
      slots: MemorySlotStore(),
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('slots', () {
    test('the first mod lands in pak01', () async {
      final mod = addLibraryMod('Skin', ['skin_dir.vpk']);

      await installer.enable('Skin', mod);

      expect(File(p.join(addonsDir(), 'pak01_dir.vpk')).existsSync(), isTrue);
      expect(installer.slotOf('Skin'), 1);
    });

    test('the next mod takes the next free number', () async {
      await installer.enable('A', addLibraryMod('A', ['a_dir.vpk']));
      await installer.enable('B', addLibraryMod('B', ['b_dir.vpk']));

      expect(installer.slotOf('B'), 2);
      expect(File(p.join(addonsDir(), 'pak02_dir.vpk')).existsSync(), isTrue);
    });

    test('a freed number is reused instead of climbing forever', () async {
      await installer.enable('A', addLibraryMod('A', ['a_dir.vpk']));
      await installer.enable('B', addLibraryMod('B', ['b_dir.vpk']));
      await installer.disable('A');

      await installer.enable('C', addLibraryMod('C', ['c_dir.vpk']));

      expect(installer.slotOf('C'), 1);
    });

    test('load order can be changed by moving a mod to another number', () async {
      await installer.enable('A', addLibraryMod('A', ['a_dir.vpk']));
      await installer.enable('B', addLibraryMod('B', ['b_dir.vpk']));

      await installer.setSlot('B', 1);

      expect(installer.slotOf('B'), 1);
      expect(installer.slotOf('A'), isNot(1));
      expect(File(p.join(addonsDir(), 'pak01_dir.vpk')).readAsStringSync(),
          'b_dir.vpk');
    });

    test('running out of numbers fails with a readable error', () async {
      for (var i = 1; i <= 99; i++) {
        await installer.enable('mod$i', addLibraryMod('mod$i', ['m_dir.vpk']));
      }

      expect(
        () => installer.enable('one too many',
            addLibraryMod('one too many', ['x_dir.vpk'])),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('99'),
          ),
        ),
      );
    });
  });

  group('files', () {
    test('chunk files keep the numbering of their index', () async {
      final mod = addLibraryMod('Big', [
        'big_dir.vpk',
        'big_000.vpk',
        'big_001.vpk',
      ]);

      await installer.enable('Big', mod);

      for (final name in ['pak01_dir.vpk', 'pak01_000.vpk', 'pak01_001.vpk']) {
        expect(File(p.join(addonsDir(), name)).existsSync(), isTrue,
            reason: name);
      }
    });

    test('disabling removes every file of that mod', () async {
      await installer.enable(
        'Big',
        addLibraryMod('Big', ['big_dir.vpk', 'big_000.vpk']),
      );

      await installer.disable('Big');

      expect(Directory(addonsDir()).listSync(), isEmpty);
      expect(installer.isEnabled('Big'), isFalse);
    });

    test('a mod without a vpk is rejected', () async {
      final mod = addLibraryMod('Readme', ['readme.txt']);

      expect(
        () => installer.enable('Readme', mod),
        throwsA(isA<StateError>()),
      );
    });

    test('a single vpk without the _dir suffix still installs', () async {
      await installer.enable('Plain', addLibraryMod('Plain', ['plain.vpk']));

      expect(File(p.join(addonsDir(), 'pak01_dir.vpk')).existsSync(), isTrue);
    });

    test('a mod whose files were deleted by hand reads as disabled', () async {
      await installer.enable('Skin', addLibraryMod('Skin', ['skin_dir.vpk']));
      File(p.join(addonsDir(), 'pak01_dir.vpk')).deleteSync();

      expect(installer.isEnabled('Skin'), isFalse);
    });
  });
}
