import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/services/defender_exclusions.dart';

ProcessResult _out(String stdout, {int code = 0, String stderr = ''}) =>
    ProcessResult(0, code, stdout, stderr);

void main() {
  group('which paths matter', () {
    test('covers the app, its data and the game binaries folder', () {
      final paths = DefenderExclusions.pathsFor(
        installDir: r'C:\Program Files\Modlinq',
        appDataDir: r'C:\Users\Chris\AppData\Roaming\modlinq',
        nteGamePath: r'D:\NTE',
      );

      expect(paths, [
        r'C:\Program Files\Modlinq',
        r'C:\Users\Chris\AppData\Roaming\modlinq',
        r'D:\NTE\Client\WindowsNoEditor\HT\Binaries\Win64',
      ]);
    });

    test('without a configured game only the app folders are listed', () {
      final paths = DefenderExclusions.pathsFor(
        installDir: r'C:\Modlinq',
        appDataDir: r'C:\data',
      );

      expect(paths.length, 2);
    });
  });

  group('what is still missing', () {
    DefenderExclusions service(String existing) => DefenderExclusions(
      supported: true,
      run: (_) async => _out(existing),
    );

    test('an exclusion that is already there is not offered again', () async {
      final missing = await service(
        'C:\\Program Files\\Modlinq\nC:\\other',
      ).missing([r'C:\Program Files\Modlinq', r'C:\data']);

      expect(missing, [r'C:\data']);
    });

    test('a parent exclusion covers the folder below it', () async {
      final missing = await service(r'D:\NTE').missing([
        r'D:\NTE\Client\WindowsNoEditor\HT\Binaries\Win64',
      ]);

      expect(missing, isEmpty);
    });

    test('matching ignores case, because Windows paths do', () async {
      final missing = await service(r'c:\program files\modlinq').missing([
        r'C:\Program Files\Modlinq',
      ]);

      expect(missing, isEmpty);
    });

    test('when Defender cannot be asked, everything counts as missing', () async {
      final service = DefenderExclusions(
        supported: true,
        run: (_) async => throw const ProcessException('powershell', []),
      );

      expect(await service.missing([r'C:\a', r'C:\b']), [r'C:\a', r'C:\b']);
    });
  });

  group('the command', () {
    test('asks for elevation and adds one path per call', () {
      final command = DefenderExclusions.addCommand([r'C:\a', r'C:\b']);

      expect(command.last, contains('-Verb RunAs'));
      expect(command.last, contains('Add-MpPreference'));
      // Two separate calls: one bad path must not take the other with it.
      expect("Add-MpPreference".allMatches(command.last).length, 2);
    });

    test('removal uses the matching cmdlet, so it is reversible', () {
      expect(
        DefenderExclusions.removeCommand([r'C:\a']).last,
        contains('Remove-MpPreference'),
      );
    });

    test("a quote in a path cannot end the powershell argument", () {
      final command = DefenderExclusions.addCommand([r"C:\it's here"]);

      expect(command.last, contains("it''''s here"));
    });

    test('a failed call is reported rather than silently ignored', () async {
      final service = DefenderExclusions(
        supported: true,
        run: (_) async => _out('', code: 1, stderr: 'access denied'),
      );

      await expectLater(
        service.add([r'C:\a']),
        throwsA(isA<ProcessException>()),
      );
    });

    test('a platform without Defender refuses instead of pretending', () async {
      final service = DefenderExclusions(
        supported: false,
        run: (_) async => _out(''),
      );

      await expectLater(service.add([r'C:\a']), throwsUnsupportedError);
      expect(await service.current(), isEmpty);
    });
  });
}
