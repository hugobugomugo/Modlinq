import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/services/config_service.dart';
import 'package:modlinq/services/defender_exclusions.dart';
import 'package:modlinq/services/diagnostics_report.dart';
import 'package:modlinq/services/integrity_service.dart';

const _asi = 'assets/nte_loader/loader.asi';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory installDir;
  late ConfigService config;

  String _manifest(String body) => jsonEncode({
    'files': [
      {
        'asset': _asi,
        'bytes': utf8.encode(body).length,
        'sha256': sha256.convert(utf8.encode(body)).toString(),
      },
    ],
  });

  DiagnosticsReport _report({
    String manifestBody = 'loader',
    DefenderExclusions? defender,
  }) => DiagnosticsReport(
    config: config,
    integrity: IntegrityService(
      installDir: installDir,
      readManifest: () async => _manifest(manifestBody),
    ),
    defender:
        defender ?? DefenderExclusions(supported: false, run: (_) async => throw 'no'),
    logTail: () => 'LOGLINE-ONE\nLOGLINE-TWO',
    now: () => DateTime.utc(2026, 9, 28, 14, 5, 6),
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('modlinq_diag_');
    installDir = Directory(p.join(tmp.path, 'app'))..createSync();
    config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('every section is present even with nothing configured', () async {
    final text = await _report().build();

    for (final section in [
      '== modlinq ==',
      '== bundle ==',
      '== defender ==',
      '== config ==',
      '== nte ==',
      '== deadlock ==',
      '== zzz / wuwa ==',
      '== log ==',
    ]) {
      expect(text, contains(section), reason: 'missing $section');
    }
  });

  test('the log tail is carried into the report', () async {
    expect(await _report().build(), contains('LOGLINE-TWO'));
  });

  test('stored settings appear, including keys with no typed getter', () async {
    await config.setNteGamePath(r'D:\NTE');
    SharedPreferences.setMockInitialValues({'some_legacy_key': 'kept'});
    final fresh = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );

    final text = await DiagnosticsReport(
      config: fresh,
      integrity: IntegrityService(
        installDir: installDir,
        readManifest: () async => _manifest('loader'),
      ),
      defender: DefenderExclusions(supported: false, run: (_) async => throw 'no'),
      logTail: () => '',
    ).build();

    expect(text, contains('some_legacy_key = kept'));
  });

  test('a missing bundled file is called out as damaged', () async {
    final text = await _report().build();

    expect(text, contains('DAMAGED'));
    expect(text, contains('missing'));
    expect(text, contains(_asi));
  });

  test('an intact bundle reads as intact', () async {
    final file = File(p.join(installDir.path, 'data', 'flutter_assets', _asi))
      ..createSync(recursive: true)
      ..writeAsStringSync('loader');
    expect(file.existsSync(), isTrue);

    expect(await _report().build(), contains('intact'));
  });

  test('a section that throws does not take the report with it', () async {
    final text = await DiagnosticsReport(
      config: config,
      integrity: IntegrityService(
        installDir: installDir,
        readManifest: () async => 'not json at all',
      ),
      defender: DefenderExclusions(supported: false, run: (_) async => throw 'no'),
      logTail: () => 'STILL-HERE',
    ).build();

    expect(text, contains('!! section failed'));
    expect(text, contains('STILL-HERE'));
    expect(text, contains('== config =='));
  });

  test('missing defender exclusions are named', () async {
    await config.setNteGamePath(r'D:\NTE');

    final text = await _report(
      defender: DefenderExclusions(
        supported: true,
        run: (_) async => ProcessResult(0, 0, '', ''),
      ),
    ).build();

    expect(text, contains('INCOMPLETE'));
    expect(text, contains(r'D:\NTE\Client\WindowsNoEditor\HT\Binaries\Win64'));
  });

  test('the file name carries a sortable timestamp', () async {
    final file = await _report().writeToLogFolder();

    expect(p.basename(file.path), startsWith('modlinq-diagnostics-2026-09-28'));
    expect(file.readAsStringSync(), contains('== modlinq =='));
    file.deleteSync();
  });
}
