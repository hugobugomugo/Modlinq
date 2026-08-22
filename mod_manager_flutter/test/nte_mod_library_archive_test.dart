import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/models/nte_mod.dart';
import 'package:modlinq/services/nte_mod_library.dart';

/// Path to a 7-Zip binary, or null when the machine has none.
///
/// rar and 7z support is only real where the tool exists, so the tests that
/// need it skip rather than fail on machines without it.
String? locateSevenZip() {
  try {
    final result = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      ['7z'],
    );
    if (result.exitCode != 0) return null;
    return result.stdout
        .toString()
        .split(RegExp(r'[\r\n]+'))
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
        .trim();
  } catch (_) {
    return null;
  }
}

void main() {
  final sevenZip = locateSevenZip();
  final noSevenZip = sevenZip == null ? '7-Zip is not installed here' : null;

  late Directory tmp;
  late NteModLibrary library;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('nte_archive_');
    library = NteModLibrary(p.join(tmp.path, 'library'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// A UE mod: the .pak is useless without its .ucas and .utoc companions, so
  /// a partial extraction has to be treated as a failure.
  Archive modArchive() => Archive()
    ..add(ArchiveFile.string('CoolSkin/skin.pak', 'pak-bytes'))
    ..add(ArchiveFile.string('CoolSkin/skin.ucas', 'ucas-bytes'))
    ..add(ArchiveFile.string('CoolSkin/skin.utoc', 'utoc-bytes'));

  File fixture(String name, List<int> bytes) =>
      File(p.join(tmp.path, name))..writeAsBytesSync(bytes);

  void expectFullyImported(NteMod? mod) {
    expect(mod, isNotNull);
    expect(
      mod!.files.map(p.basename),
      containsAll(['skin.pak', 'skin.ucas', 'skin.utoc']),
    );
    for (final file in mod.files) {
      expect(File(file).lengthSync(), greaterThan(0), reason: file);
    }
  }

  test('imports every file of a zip archive', () async {
    final file = fixture('CoolSkin.zip', ZipEncoder().encodeBytes(modArchive()));

    expectFullyImported(await library.importArchive(file.path));
  });

  test('imports every file of a gzip-compressed tarball', () async {
    final tar = TarEncoder().encodeBytes(modArchive());
    final file = fixture('CoolSkin.tar.gz', GZipEncoder().encodeBytes(tar));

    expectFullyImported(await library.importArchive(file.path));
  });

  test('imports every file of an xz-compressed tarball', () async {
    final tar = TarEncoder().encodeBytes(modArchive());
    final file = fixture('CoolSkin.tar.xz', XZEncoder().encodeBytes(tar));

    expectFullyImported(await library.importArchive(file.path));
  });

  test('names a tarball mod without leaving .tar in the name', () async {
    final tar = TarEncoder().encodeBytes(modArchive());
    final file = fixture('CoolSkin.tar.gz', GZipEncoder().encodeBytes(tar));

    final mod = await library.importArchive(file.path);

    expect(mod!.name, 'CoolSkin');
  });

  test('returns null when the archive holds no installable payload', () async {
    final readme = Archive()
      ..add(ArchiveFile.string('CoolSkin/readme.txt', 'hello'));
    final file = fixture('CoolSkin.zip', ZipEncoder().encodeBytes(readme));

    expect(await library.importArchive(file.path), isNull);
  });

  /// Packs the mod with the system 7-Zip, the only way to get a real fixture.
  File sevenZipFixture(String name) {
    final source = Directory(p.join(tmp.path, 'src', 'CoolSkin'))
      ..createSync(recursive: true);
    for (final entry in {
      'skin.pak': 'pak-bytes',
      'skin.ucas': 'ucas-bytes',
      'skin.utoc': 'utoc-bytes',
    }.entries) {
      File(p.join(source.path, entry.key)).writeAsStringSync(entry.value);
    }

    final target = p.join(tmp.path, name);
    final result = Process.runSync(sevenZip!, ['a', '-y', target, source.path]);
    expect(result.exitCode, 0, reason: result.stderr.toString());

    return File(target);
  }

  test('imports every file of a 7z archive', () async {
    final mod = await library.importArchive(sevenZipFixture('CoolSkin.7z').path);

    expectFullyImported(mod);
    expect(mod!.name, 'CoolSkin');
  }, skip: noSevenZip);

  test('counts rar and 7z among the formats it accepts', () {
    expect(NteModLibrary.isSupportedArchive('CoolSkin.rar'), isTrue);
    expect(NteModLibrary.isSupportedArchive('CoolSkin.7z'), isTrue);
    expect(NteModLibrary.isSupportedArchive('CoolSkin.pak'), isFalse);
  });

  test('reports a corrupt archive instead of silently skipping it', () async {
    final file = fixture('CoolSkin.7z', [1, 2, 3]);

    expect(
      () => library.importArchive(file.path),
      throwsA(isA<StateError>()),
    );
  }, skip: noSevenZip);

  test('rejects a file that is not an archive at all', () async {
    final file = fixture('CoolSkin.pak', [1, 2, 3]);

    expect(
      () => library.importArchive(file.path),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('leaves no staging directory behind', () async {
    Set<String> stagingDirs() => Directory.systemTemp
        .listSync()
        .whereType<Directory>()
        .map((d) => p.basename(d.path))
        .where((name) => name.startsWith('nte_import_'))
        .toSet();

    // Older builds leaked staging folders, so only count what this run adds.
    final before = stagingDirs();
    final file = fixture('CoolSkin.zip', ZipEncoder().encodeBytes(modArchive()));

    await library.importArchive(file.path);

    expect(stagingDirs().difference(before), isEmpty);
  });
}
