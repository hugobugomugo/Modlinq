import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/archive_service.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('archive_service_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  /// A one-folder mod, the shape the importer expects to find in an archive.
  Archive modArchive() => Archive()
    ..add(ArchiveFile.string('CoolSkin/mod.ini', '[Constants]'))
    ..add(ArchiveFile.string('CoolSkin/texture.dds', 'pixels'));

  List<int> tarBytes() => TarEncoder().encodeBytes(modArchive());

  File fixture(String name, List<int> bytes) =>
      File(p.join(tmp.path, name))..writeAsBytesSync(bytes);

  Future<ArchiveExtractionResult> extract(File archiveFile) {
    final destination = Directory(p.join(tmp.path, 'out'))
      ..createSync(recursive: true);
    return ArchiveService.extractArchive(
      archiveFile: archiveFile,
      destinationDir: destination,
    );
  }

  /// Asserts the mod folder and both payload files landed on disk.
  void expectModExtracted(ArchiveExtractionResult result) {
    expect(result.error, isNull);
    expect(result.success, isTrue);
    expect(result.extractedFolders, hasLength(1));

    final folder = result.extractedFolders!.single;
    expect(p.basename(folder), 'CoolSkin');
    expect(File(p.join(folder, 'mod.ini')).existsSync(), isTrue);
    expect(File(p.join(folder, 'texture.dds')).existsSync(), isTrue);
  }

  test('extracts a zip archive', () async {
    final file = fixture('Skin.zip', ZipEncoder().encodeBytes(modArchive()));

    expectModExtracted(await extract(file));
  });

  test('extracts a plain tar archive', () async {
    final file = fixture('Skin.tar', tarBytes());

    expectModExtracted(await extract(file));
  });

  test('extracts a gzip-compressed tarball', () async {
    final file = fixture('Skin.tar.gz', GZipEncoder().encodeBytes(tarBytes()));

    expectModExtracted(await extract(file));
  });

  test('extracts a bzip2-compressed tarball', () async {
    final file = fixture('Skin.tar.bz2', BZip2Encoder().encodeBytes(tarBytes()));

    expectModExtracted(await extract(file));
  });

  test('extracts an xz-compressed tarball', () async {
    final file = fixture('Skin.tar.xz', XZEncoder().encodeBytes(tarBytes()));

    expectModExtracted(await extract(file));
  });

  test('extracts a .tgz shorthand tarball', () async {
    final file = fixture('Skin.tgz', GZipEncoder().encodeBytes(tarBytes()));

    expectModExtracted(await extract(file));
  });

  test('wraps loose archive entries in a folder named after the archive', () async {
    final loose = Archive()..add(ArchiveFile.string('mod.ini', '[Constants]'));
    final file = fixture('LooseSkin.tar', TarEncoder().encodeBytes(loose));

    final result = await extract(file);

    expect(result.success, isTrue);
    final folder = result.extractedFolders!.single;
    expect(p.basename(folder), 'LooseSkin');
    expect(File(p.join(folder, 'mod.ini')).existsSync(), isTrue);
  });

  test('names the wrapper folder without leaving .tar in it', () async {
    final loose = Archive()..add(ArchiveFile.string('mod.ini', '[Constants]'));
    final tar = TarEncoder().encodeBytes(loose);
    final file = fixture('LooseSkin.tar.gz', GZipEncoder().encodeBytes(tar));

    final result = await extract(file);

    expect(p.basename(result.extractedFolders!.single), 'LooseSkin');
  });

  group('unpackInto', () {
    test('unpacks straight into the destination without wrapping', () async {
      final tar = TarEncoder().encodeBytes(modArchive());
      final file = fixture('Skin.tar.gz', GZipEncoder().encodeBytes(tar));
      final destination = Directory(p.join(tmp.path, 'raw'))
        ..createSync(recursive: true);

      final error = await ArchiveService.unpackInto(
        archiveFile: file,
        destination: destination,
      );

      expect(error, isNull);
      expect(
        File(p.join(destination.path, 'CoolSkin', 'mod.ini')).existsSync(),
        isTrue,
      );
    });

    test('returns the reason when the archive cannot be read', () async {
      final file = fixture('Skin.tar.gz', [1, 2, 3]);
      final destination = Directory(p.join(tmp.path, 'raw'))
        ..createSync(recursive: true);

      final error = await ArchiveService.unpackInto(
        archiveFile: file,
        destination: destination,
      );

      expect(error, isNotNull);
    });

    test('names an unsupported format as the reason', () async {
      final file = fixture('Skin.pak', [1, 2, 3]);
      final destination = Directory(p.join(tmp.path, 'raw'))
        ..createSync(recursive: true);

      final error = await ArchiveService.unpackInto(
        archiveFile: file,
        destination: destination,
      );

      expect(error, contains('not supported'));
    });
  });

  test('fails for a file that is not an archive', () async {
    final file = fixture('Skin.pak', [1, 2, 3]);

    final result = await extract(file);

    expect(result.success, isFalse);
    expect(result.error, isNotNull);
  });

  test('fails gracefully on a corrupt rar instead of throwing', () async {
    final file = fixture('Skin.rar', [1, 2, 3]);

    final result = await extract(file);

    expect(result.success, isFalse);
    expect(result.error, isNotNull);
  });
}
