import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/integrity_repair.dart';
import 'package:modlinq/services/integrity_service.dart';

const _asi = 'assets/nte_loader/loader.asi';
const _dll = 'assets/nte_loader/subloader.dll';
const _asiBody = 'the-real-loader';
const _dllBody = 'the-real-subloader';

void main() {
  late Directory tmp;
  late Directory installDir;

  String _flutterAssetPath(String key) =>
      p.join(installDir.path, 'data', 'flutter_assets', key);

  void _place(String key, String content) {
    File(_flutterAssetPath(key))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String _manifest() => jsonEncode({
    'files': [
      for (final e in {_asi: _asiBody, _dll: _dllBody}.entries)
        {
          'asset': e.key,
          'bytes': utf8.encode(e.value).length,
          'sha256': sha256.convert(utf8.encode(e.value)).toString(),
        },
    ],
  });

  /// A release zip laid out the way the real one is.
  File _package({String asiBody = _asiBody}) {
    final archive = Archive();
    for (final e in {_asi: asiBody, _dll: _dllBody}.entries) {
      final bytes = utf8.encode(e.value);
      archive.addFile(
        ArchiveFile('data/flutter_assets/${e.key}', bytes.length, bytes),
      );
    }
    archive.addFile(ArchiveFile('modlinq.exe', 4, utf8.encode('exe!')));

    final zip = File(p.join(tmp.path, 'release.zip'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return zip;
  }

  IntegrityService _integrity() => IntegrityService(
    installDir: installDir,
    readManifest: () async => _manifest(),
  );

  /// Stands in for the elevated copy step.
  late Map<String, String> placed;

  IntegrityRepair _repair({File? package}) => IntegrityRepair(
    integrity: _integrity(),
    fetchPackage: () async => package ?? _package(),
    placeFiles: (fromTo) async {
      placed = fromTo;
      for (final entry in fromTo.entries) {
        File(entry.value)
          ..createSync(recursive: true)
          ..writeAsBytesSync(File(entry.key).readAsBytesSync());
      }
    },
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('modlinq_repair_');
    installDir = Directory(p.join(tmp.path, 'app'))..createSync();
    placed = {};
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('a deleted file is put back and the install reads healthy', () async {
    _place(_dll, _dllBody);

    final report = await _integrity().check();
    expect(report.broken.single.assetKey, _asi);

    final result = await _repair().run(report);

    expect(result.restored, [_asi]);
    expect(File(_flutterAssetPath(_asi)).readAsStringSync(), _asiBody);
    expect((await _integrity().check()).healthy, isTrue);
  });

  test('only the broken files are touched', () async {
    _place(_dll, _dllBody);

    await _repair().run(await _integrity().check());

    expect(placed.keys.length, 1);
    expect(placed.values.single, _flutterAssetPath(_asi));
  });

  test('a healthy install downloads nothing', () async {
    _place(_asi, _asiBody);
    _place(_dll, _dllBody);

    var fetched = false;
    final repair = IntegrityRepair(
      integrity: _integrity(),
      fetchPackage: () async {
        fetched = true;
        return _package();
      },
      placeFiles: (_) async {},
    );

    final result = await repair.run(await _integrity().check());

    expect(result.restored, isEmpty);
    expect(fetched, isFalse);
  });

  test('a package whose bytes do not match the manifest is refused', () async {
    _place(_dll, _dllBody);

    final repair = _repair(package: _package(asiBody: 'tampered-loader'));

    await expectLater(
      repair.run(await _integrity().check()),
      throwsA(isA<IntegrityRepairException>()),
    );
    expect(File(_flutterAssetPath(_asi)).existsSync(), isFalse);
  });

  test('a package missing the file fails loudly', () async {
    _place(_dll, _dllBody);

    final empty = File(p.join(tmp.path, 'empty.zip'))
      ..writeAsBytesSync(ZipEncoder().encodeBytes(Archive()));

    await expectLater(
      _repair(package: empty).run(await _integrity().check()),
      throwsA(isA<IntegrityRepairException>()),
    );
  });
}
