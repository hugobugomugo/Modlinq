import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/nte_mod_library.dart';

void _writeFile(String path) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsStringSync('x');
}

void main() {
  late Directory tmp;
  late NteModLibrary library;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nte_edit_');
    library = NteModLibrary(p.join(tmp.path, 'library'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void addMod(String name, List<String> files) {
    for (final file in files) {
      _writeFile(p.join(library.rootPath, name, file));
    }
  }

  group('renameMod', () {
    test('moves the folder and keeps the payload', () {
      addMod('OldName', ['skin.pak']);

      final renamed = library.renameMod('OldName', 'NewName');

      expect(renamed.name, 'NewName');
      expect(renamed.files.map(p.basename), ['skin.pak']);
      expect(library.findMod('OldName'), isNull);
      expect(library.findMod('NewName'), isNotNull);
    });

    test('trims surrounding whitespace', () {
      addMod('Mod', ['a.pak']);

      expect(library.renameMod('Mod', '  Tidy  ').name, 'Tidy');
    });

    test('renaming to the same name is a no-op', () {
      addMod('Same', ['a.pak']);

      expect(library.renameMod('Same', 'Same').name, 'Same');
      expect(library.findMod('Same'), isNotNull);
    });

    test('rejects an empty name', () {
      addMod('Mod', ['a.pak']);

      expect(() => library.renameMod('Mod', '   '), throwsArgumentError);
    });

    test('rejects path separators so a rename cannot escape the library', () {
      addMod('Mod', ['a.pak']);

      expect(() => library.renameMod('Mod', '../evil'), throwsArgumentError);
      expect(() => library.renameMod('Mod', 'sub/name'), throwsArgumentError);
    });

    test('rejects a name that is already taken', () {
      addMod('First', ['a.pak']);
      addMod('Second', ['b.pak']);

      expect(() => library.renameMod('First', 'Second'), throwsStateError);
    });

    test('rejects renaming a mod that does not exist', () {
      expect(() => library.renameMod('Ghost', 'Anything'), throwsStateError);
    });
  });

  group('preview images', () {
    test('returns null when the mod has no preview', () {
      addMod('Plain', ['a.pak']);

      expect(library.previewImageFor('Plain'), isNull);
    });

    test('stores an image and reads it back', () {
      addMod('WithArt', ['a.pak']);

      final path = library.setPreviewImage('WithArt', [1, 2, 3]);

      expect(p.basename(path), 'preview.png');
      expect(library.previewImageFor('WithArt'), path);
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('replacing a preview leaves only the new image', () {
      addMod('WithArt', ['a.pak']);
      _writeFile(p.join(library.rootPath, 'WithArt', 'old_shot.jpg'));

      library.setPreviewImage('WithArt', [9]);

      final images = Directory(p.join(library.rootPath, 'WithArt'))
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .where((name) => name != 'a.pak')
          .toList();
      expect(images, ['preview.png']);
    });

    test('clearing a preview removes it and leaves the payload alone', () {
      addMod('WithArt', ['a.pak']);
      library.setPreviewImage('WithArt', [1, 2, 3]);
      expect(library.previewImageFor('WithArt'), isNotNull);

      expect(library.clearPreviewImage('WithArt'), isTrue);

      expect(library.previewImageFor('WithArt'), isNull);
      final left = Directory(p.join(library.rootPath, 'WithArt'))
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toList();
      expect(left, ['a.pak']);
    });

    test('clearing a preview that does not exist reports nothing removed', () {
      addMod('NoArt', ['a.pak']);
      expect(library.clearPreviewImage('NoArt'), isFalse);
      expect(library.clearPreviewImage('MissingMod'), isFalse);
    });

    test('a preview image is never treated as installable payload', () {
      addMod('WithArt', ['a.pak']);
      library.setPreviewImage('WithArt', [1]);

      expect(library.findMod('WithArt')!.files.map(p.basename), ['a.pak']);
    });

    test('icon.png is not offered as a preview', () {
      addMod('Iconed', ['a.pak', 'icon.png']);

      expect(library.previewImageFor('Iconed'), isNull);
    });

    test('rejects an unknown mod', () {
      expect(() => library.setPreviewImage('Ghost', [1]), throwsStateError);
    });
  });
}
