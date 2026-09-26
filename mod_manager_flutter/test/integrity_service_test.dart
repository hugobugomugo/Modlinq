import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/integrity_service.dart';

const _asi = 'assets/nte_loader/loader.asi';
const _dll = 'assets/nte_loader/subloader.dll';

void main() {
  late Directory tmp;
  late Directory installDir;

  /// Writes [content] where the app would find [assetKey] at runtime.
  File _place(String assetKey, String content) {
    final file = File(
      p.join(installDir.path, 'data', 'flutter_assets', assetKey),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  String _manifest(Map<String, String> contents) => jsonEncode({
    'files': [
      for (final entry in contents.entries)
        {
          'asset': entry.key,
          'bytes': utf8.encode(entry.value).length,
          'sha256': sha256.convert(utf8.encode(entry.value)).toString(),
        },
    ],
  });

  IntegrityService _service(Map<String, String> manifest) => IntegrityService(
    installDir: installDir,
    readManifest: () async => _manifest(manifest),
  );

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('modlinq_integrity_');
    installDir = Directory(p.join(tmp.path, 'app'))..createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('an untouched install is healthy', () async {
    _place(_asi, 'loader-bytes');
    _place(_dll, 'sub-bytes');

    final report = await _service({
      _asi: 'loader-bytes',
      _dll: 'sub-bytes',
    }).check();

    expect(report.healthy, isTrue);
    expect(report.broken, isEmpty);
    expect(report.files.every((f) => f.state == IntegrityState.ok), isTrue);
  });

  test('a file antivirus removed is reported as missing, with its path', () async {
    _place(_dll, 'sub-bytes');

    final report = await _service({
      _asi: 'loader-bytes',
      _dll: 'sub-bytes',
    }).check();

    expect(report.healthy, isFalse);
    final broken = report.broken.single;
    expect(broken.assetKey, _asi);
    expect(broken.state, IntegrityState.missing);
    expect(
      broken.path,
      p.join(installDir.path, 'data', 'flutter_assets', _asi),
    );
  });

  test('a file of the wrong size is corrupt', () async {
    _place(_asi, 'truncated');

    final report = await _service({_asi: 'loader-bytes'}).check();

    expect(report.broken.single.state, IntegrityState.corrupt);
    expect(report.broken.single.actualBytes, 9);
  });

  test('a swapped file of the same size is still corrupt', () async {
    // Same length, different content: only the hash can tell these apart.
    _place(_asi, 'AAAAAAAAAAAA');

    final report = await _service({_asi: 'loader-bytes'}).check();

    expect(report.broken.single.state, IntegrityState.corrupt);
  });

  test('an unreadable manifest fails loudly rather than reporting healthy', () {
    final service = IntegrityService(
      installDir: installDir,
      readManifest: () async => 'not json',
    );

    expect(service.check(), throwsA(isA<IntegrityManifestException>()));
  });
}
