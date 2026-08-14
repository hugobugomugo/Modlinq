import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:mod_manager_flutter/services/ntemm_importer.dart';
import 'package:mod_manager_flutter/services/nte_mod_library.dart';

void _writeFile(String path) {
  Directory(p.dirname(path)).createSync(recursive: true);
  File(path).writeAsStringSync('x');
}

void main() {
  late Directory tmp;
  late String ntemmRoot;
  late NteModLibrary library;
  late NteMmImporter importer;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ntemm_import_');
    ntemmRoot = p.join(tmp.path, 'NTEMM_Mods');
    library = NteModLibrary(p.join(tmp.path, 'library'));
    importer = NteMmImporter(library);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void addNtemmMod(String name, List<String> files) {
    for (final file in files) {
      _writeFile(p.join(ntemmRoot, name, file));
    }
  }

  test('imports every mod folder and leaves the source untouched', () {
    addNtemmMod('SkinA', ['a.pak', 'a.ucas', 'icon.ico']);
    addNtemmMod('PluginB', ['b.asi']);

    final result = importer.importFrom(ntemmRoot);

    expect(result.importedCount, 2);
    expect(result.skipped, isEmpty);
    expect(library.listMods().map((m) => m.name), ['PluginB', 'SkinA']);
    expect(File(p.join(ntemmRoot, 'SkinA', 'a.pak')).existsSync(), isTrue);
  });

  test('copies companion files alongside the pak', () {
    addNtemmMod('SkinA', ['a.pak', 'a.ucas', 'a.utoc']);

    importer.importFrom(ntemmRoot);

    final mod = library.findMod('SkinA')!;
    expect(mod.files.map(p.basename), containsAll(['a.pak', 'a.ucas', 'a.utoc']));
  });

  test('skips mods already in the library instead of failing', () {
    addNtemmMod('SkinA', ['a.pak']);
    importer.importFrom(ntemmRoot);

    final second = importer.importFrom(ntemmRoot);

    expect(second.importedCount, 0);
    expect(second.skipped['SkinA'], 'Already in the library');
  });

  test('skips folders without installable files', () {
    addNtemmMod('JustNotes', ['readme.txt']);

    final result = importer.importFrom(ntemmRoot);

    expect(result.importedCount, 0);
    expect(result.skipped['JustNotes'], 'No .pak or .asi files found');
  });

  test('reports progress for each mod', () {
    addNtemmMod('One', ['a.pak']);
    addNtemmMod('Two', ['b.pak']);

    final seen = <String>[];
    importer.importFrom(ntemmRoot, onProgress: (name, index, total) {
      seen.add('$index/$total $name');
    });

    expect(seen, ['1/2 One', '2/2 Two']);
  });

  test('returns nothing for a missing library path', () {
    final result = importer.importFrom(p.join(tmp.path, 'nope'));

    expect(result.importedCount, 0);
    expect(result.skipped, isEmpty);
  });

  test('modFoldersIn ignores loose files', () {
    addNtemmMod('SkinA', ['a.pak']);
    _writeFile(p.join(ntemmRoot, 'stray.txt'));

    expect(NteMmImporter.modFoldersIn(ntemmRoot).map(p.basename), ['SkinA']);
  });
}
