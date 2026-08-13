import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mod_manager_flutter/models/nte_mod.dart';
import 'package:mod_manager_flutter/services/nte_mod_installer.dart';
import 'package:mod_manager_flutter/services/nte_mod_library.dart';

void _writeFile(String path, [String content = 'x']) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsStringSync(content);
}

void main() {
  late Directory tmp;
  late String libraryRoot;
  late String gameRoot;
  late NteModLibrary library;
  late NteModInstaller installer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nte_mods_');
    libraryRoot = p.join(tmp.path, 'library');
    gameRoot = p.join(tmp.path, 'game');
    library = NteModLibrary(libraryRoot);
    installer = NteModInstaller(gameRoot);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Creates a mod folder in the library with the given payload files.
  NteMod addLibraryMod(String name, List<String> relativeFiles) {
    for (final relative in relativeFiles) {
      _writeFile(p.join(libraryRoot, name, relative));
    }
    return library.findMod(name)!;
  }

  group('library', () {
    test('lists imported mods sorted by name', () {
      addLibraryMod('Zebra', ['z.pak']);
      addLibraryMod('alpha', ['a.pak']);

      expect(library.listMods().map((m) => m.name), ['alpha', 'Zebra']);
    });

    test('ignores helper files when collecting payload', () {
      final mod = addLibraryMod('Skin', [
        'skin.pak',
        'mod.json',
        'icon.png',
        'preview.jpg',
      ]);

      expect(mod.files.map(p.basename), ['skin.pak']);
      expect(mod.isPak, isTrue);
      expect(mod.isAsi, isFalse);
    });

    test('classifies asi mods', () {
      final mod = addLibraryMod('Plugin', ['plugin.asi']);
      expect(mod.isAsi, isTrue);
      expect(mod.isPak, isFalse);
    });

    test('a mod without pak or asi files is not installable', () {
      final mod = addLibraryMod('Readme', ['notes.txt']);
      expect(mod.isInstallable, isFalse);
    });

    test('importDirectory copies the source and leaves it in place', () {
      final source = p.join(tmp.path, 'src', 'CoolMod');
      _writeFile(p.join(source, 'cool.pak'));

      final imported = library.importDirectory(source)!;

      expect(imported.name, 'CoolMod');
      expect(File(p.join(libraryRoot, 'CoolMod', 'cool.pak')).existsSync(), isTrue);
      expect(File(p.join(source, 'cool.pak')).existsSync(), isTrue);
    });

    test('importDirectory returns null when there is no payload', () {
      final source = p.join(tmp.path, 'src', 'Empty');
      _writeFile(p.join(source, 'readme.txt'));

      expect(library.importDirectory(source), isNull);
    });

    test('importDirectory rejects a duplicate name', () {
      addLibraryMod('Dupe', ['a.pak']);
      final source = p.join(tmp.path, 'src', 'Dupe');
      _writeFile(p.join(source, 'a.pak'));

      expect(() => library.importDirectory(source), throwsStateError);
    });

    test('deleteMod removes the folder', () {
      addLibraryMod('Gone', ['a.pak']);
      library.deleteMod('Gone');

      expect(library.findMod('Gone'), isNull);
    });
  });

  group('installer', () {
    test('enable copies pak files into ~mods and reports enabled', () {
      final mod = addLibraryMod('PakMod', ['content.pak']);

      installer.enable(mod);

      final installed = p.join(installer.pakTarget, 'PakMod', 'content.pak');
      expect(File(installed).existsSync(), isTrue);
      expect(installer.isEnabled(mod), isTrue);
    });

    test('enable preserves nested folder layout', () {
      final mod = addLibraryMod('Nested', [p.join('sub', 'deep.pak')]);

      installer.enable(mod);

      expect(
        File(p.join(installer.pakTarget, 'Nested', 'sub', 'deep.pak')).existsSync(),
        isTrue,
      );
    });

    test('enable puts asi files next to the game binary', () {
      final mod = addLibraryMod('AsiMod', ['hook.asi']);

      installer.enable(mod);

      expect(File(p.join(installer.asiTarget, 'hook.asi')).existsSync(), isTrue);
      expect(installer.isEnabled(mod), isTrue);
    });

    test('enable honours the category folder', () {
      final mod = addLibraryMod('Skin', ['skin.pak']).copyWith(category: 'Characters');

      installer.enable(mod);

      expect(
        File(p.join(installer.pakTarget, 'Characters', 'Skin', 'skin.pak')).existsSync(),
        isTrue,
      );
      expect(installer.installedCategoryOf('Skin'), 'Characters');
    });

    test('changing category does not leave the old copy behind', () {
      final mod = addLibraryMod('Skin', ['skin.pak']);
      installer.enable(mod);

      installer.enable(mod.copyWith(category: 'Weapons'));

      expect(Directory(p.join(installer.pakTarget, 'Skin')).existsSync(), isFalse);
      expect(
        File(p.join(installer.pakTarget, 'Weapons', 'Skin', 'skin.pak')).existsSync(),
        isTrue,
      );
    });

    test('disable removes installed files but keeps the library copy', () {
      final mod = addLibraryMod('PakMod', ['content.pak']);
      installer.enable(mod);

      installer.disable(mod);

      expect(Directory(p.join(installer.pakTarget, 'PakMod')).existsSync(), isFalse);
      expect(installer.isEnabled(mod), isFalse);
      expect(File(p.join(libraryRoot, 'PakMod', 'content.pak')).existsSync(), isTrue);
    });

    test('disable finds a mod installed inside a category', () {
      final mod = addLibraryMod('Skin', ['skin.pak']).copyWith(category: 'Characters');
      installer.enable(mod);

      installer.disable(mod);

      expect(
        Directory(p.join(installer.pakTarget, 'Characters', 'Skin')).existsSync(),
        isFalse,
      );
    });

    test('disable removes only the mod\'s own asi files', () {
      final mod = addLibraryMod('AsiMod', ['hook.asi']);
      installer.enable(mod);
      _writeFile(p.join(installer.asiTarget, 'loader.asi'));

      installer.disable(mod);

      expect(File(p.join(installer.asiTarget, 'hook.asi')).existsSync(), isFalse);
      expect(File(p.join(installer.asiTarget, 'loader.asi')).existsSync(), isTrue);
    });

    test('a partially installed pak mod counts as disabled', () {
      final mod = addLibraryMod('PakMod', ['a.pak', 'b.pak']);
      installer.enable(mod);

      File(p.join(installer.pakTarget, 'PakMod', 'b.pak')).deleteSync();

      expect(installer.isEnabled(mod), isFalse);
    });

    test('enable refuses a mod with no installable files', () {
      final mod = addLibraryMod('Readme', ['notes.txt']);
      expect(() => installer.enable(mod), throwsStateError);
    });
  });

  group('apply', () {
    test('enables and disables to match the requested set', () {
      final on = addLibraryMod('TurnOn', ['on.pak']);
      final off = addLibraryMod('TurnOff', ['off.pak']);
      installer.enable(off);

      final result = installer.apply([on, off], {'TurnOn'});

      expect(result.applied, containsAll(['TurnOn', 'TurnOff']));
      expect(result.hasFailures, isFalse);
      expect(installer.isEnabled(on), isTrue);
      expect(installer.isEnabled(off), isFalse);
    });

    test('skips mods that are already in the requested state', () {
      final mod = addLibraryMod('Steady', ['a.pak']);
      installer.enable(mod);

      expect(installer.apply([mod], {'Steady'}).applied, isEmpty);
    });

    test('ignores mods with no installable files', () {
      final mod = addLibraryMod('Readme', ['notes.txt']);

      final result = installer.apply([mod], {'Readme'});

      expect(result.applied, isEmpty);
      expect(result.hasFailures, isFalse);
    });
  });
}
