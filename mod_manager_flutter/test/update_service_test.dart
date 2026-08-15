import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:modlinq/core/app_version.dart';
import 'package:modlinq/services/update_service.dart';

void main() {
  group('version parsing', () {
    test('strips the v prefix and pads missing parts', () {
      final (a, aPre) = UpdateService.parseVersion('v2.1');
      expect(a, [2, 1, 0]);
      expect(aPre, '');

      final (b, bPre) = UpdateService.parseVersion('2.1.3');
      expect(b, [2, 1, 3]);
      expect(bPre, '');

      final (c, cPre) = UpdateService.parseVersion('v3.0.0-beta.2');
      expect(c, [3, 0, 0]);
      expect(cPre, 'beta.2');
    });
  });

  group('isNewer', () {
    test('compares core numbers', () {
      expect(UpdateService.isNewer('2.0.1', '2.0.0'), isTrue);
      expect(UpdateService.isNewer('2.1.0', '2.0.9'), isTrue);
      expect(UpdateService.isNewer('3.0.0', '2.9.9'), isTrue);
      expect(UpdateService.isNewer('2.0.0', '2.0.0'), isFalse);
      expect(UpdateService.isNewer('1.9.9', '2.0.0'), isFalse);
    });

    test('does not trip over the v prefix', () {
      expect(UpdateService.isNewer('v2.1.0', '2.0.0'), isTrue);
      expect(UpdateService.isNewer('v2.0.0', '2.0.0'), isFalse);
    });

    test('10 sorts above 9, not below it', () {
      expect(UpdateService.isNewer('2.10.0', '2.9.0'), isTrue);
      expect(UpdateService.isNewer('2.9.0', '2.10.0'), isFalse);
    });

    test('a release beats its own prerelease', () {
      expect(UpdateService.isNewer('2.1.0', '2.1.0-beta.1'), isTrue);
      expect(UpdateService.isNewer('2.1.0-beta.1', '2.1.0'), isFalse);
      expect(UpdateService.isNewer('2.1.0-beta.2', '2.1.0-beta.1'), isTrue);
    });
  });

  group('checksum file', () {
    test('parses sha256sum output', () {
      const body = '''
9f2fcd0dbd2e6f0f4b0e1f7a7c2f3e4d5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d  modlinq-2.1.0-linux-x64.zip
1111111111111111111111111111111111111111111111111111111111111111 *modlinq-2.1.0-windows-x64.zip
''';
      final map = UpdateService.parseChecksums(body);
      expect(map['modlinq-2.1.0-linux-x64.zip'],
          '9f2fcd0dbd2e6f0f4b0e1f7a7c2f3e4d5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d');
      expect(map['modlinq-2.1.0-windows-x64.zip'],
          '1111111111111111111111111111111111111111111111111111111111111111');
    });

    test('ignores junk lines', () {
      expect(UpdateService.parseChecksums('not a checksum\n\n'), isEmpty);
    });
  });

  group('install kind', () {
    test('system paths are managed', () {
      expect(UpdateService.isSystemPath('/opt/modlinq'), isTrue);
      expect(UpdateService.isSystemPath('/usr/lib/modlinq'), isTrue);
      expect(UpdateService.isSystemPath(r'C:\Program Files\Modlinq'), isTrue);
    });

    test('user owned paths are not', () {
      expect(UpdateService.isSystemPath('/home/higa/apps/modlinq'), isFalse);
      expect(UpdateService.isSystemPath(r'D:\games\modlinq'), isFalse);
    });

    test('a writable user dir is portable', () async {
      final tmp = await Directory.systemTemp.createTemp('modlinq-kind');
      addTearDown(() => tmp.delete(recursive: true));
      expect(
        await UpdateService.detectInstallKind(dir: tmp),
        InstallKind.portable,
      );
    });

    test('a system dir is managed without touching the filesystem', () async {
      expect(
        await UpdateService.detectInstallKind(dir: Directory('/opt/modlinq')),
        InstallKind.managed,
      );
    });
  });

  group('checkForUpdate', () {
    Map<String, dynamic> release(String tag) => {
          'tag_name': tag,
          'body': 'notes here',
          'assets': [
            {
              'name': 'modlinq-2.1.0-linux-x64.zip',
              'browser_download_url': 'https://example.test/linux.zip',
              'size': 1234,
            },
            {
              'name': 'modlinq-2.1.0-windows-x64.zip',
              'browser_download_url': 'https://example.test/windows.zip',
              'size': 5678,
            },
            {
              'name': 'SHA256SUMS.txt',
              'browser_download_url': 'https://example.test/SHA256SUMS.txt',
              'size': 90,
            },
          ],
        };

    test('returns info when the release is newer', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response(
              jsonEncode(release('v2.1.0')),
              200,
            )),
      );
      final info = await svc.checkForUpdate(current: '2.0.0');
      expect(info, isNotNull);
      expect(info!.version, '2.1.0');
      expect(info.assetName.endsWith(UpdateService.platformAssetSuffix()), isTrue);
      expect(info.checksumUrl, 'https://example.test/SHA256SUMS.txt');
    });

    test('returns null when already current', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response(
              jsonEncode(release('v2.0.0')),
              200,
            )),
      );
      expect(await svc.checkForUpdate(current: '2.0.0'), isNull);
    });

    test('returns null when the api errors', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response('nope', 404)),
      );
      expect(await svc.checkForUpdate(current: '2.0.0'), isNull);
    });

    test('returns null when no asset matches this platform', () async {
      final svc = UpdateService(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'tag_name': 'v9.9.9',
                'body': '',
                'assets': [
                  {
                    'name': 'source.tar.gz',
                    'browser_download_url': 'https://example.test/src',
                    'size': 1,
                  }
                ],
              }),
              200,
            )),
      );
      expect(await svc.checkForUpdate(current: '2.0.0'), isNull);
    });
  });

  group('checksum verification', () {
    test('accepts a matching digest and rejects a wrong one', () async {
      final tmp = await Directory.systemTemp.createTemp('modlinq-sum');
      addTearDown(() => tmp.delete(recursive: true));
      final f = File('${tmp.path}/a.bin')..writeAsStringSync('hello');
      // sha256("hello")
      const good =
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
      final svc = UpdateService();
      expect(await svc.verifyChecksum(f, good), isTrue);
      expect(await svc.verifyChecksum(f, 'de' * 32), isFalse);
    });
  });

  group('swap script', () {
    test('waits for the pid before copying, then relaunches', () {
      final s = UpdateService.buildSwapScript(
        processId: 4242,
        stagingPath: '/tmp/stage',
        installPath: '/opt/app',
        exeName: 'modlinq',
      );
      expect(s, contains('4242'));
      expect(s, contains('/tmp/stage'));
      expect(s, contains('/opt/app'));
      expect(s, contains('modlinq'));
      // the wait must come before the copy, or we clobber a running binary
      final waitAt = Platform.isWindows ? s.indexOf('tasklist') : s.indexOf('kill -0');
      final copyAt = Platform.isWindows ? s.indexOf('xcopy') : s.indexOf('cp -a');
      expect(waitAt, greaterThanOrEqualTo(0));
      expect(copyAt, greaterThan(waitAt));
    });
  });

  group('app version', () {
    test('appVersion matches the pubspec version', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
              multiLine: true)
          .firstMatch(pubspec);
      expect(m, isNotNull, reason: 'no version line in pubspec.yaml');
      expect(appVersion, m!.group(1));
    });
  });
}
