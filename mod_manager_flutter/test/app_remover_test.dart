import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/app_remover.dart';
import 'package:modlinq/services/update_service.dart';

void main() {
  final installDir = Directory(p.join('C:', 'Program Files', 'Modlinq'));

  group('picking a method', () {
    test('an installed copy hands over to its own uninstaller', () {
      expect(
        AppRemover.methodFor(
          kind: InstallKind.installed,
          uninstallerPresent: true,
          scriptPresent: true,
        ),
        AppRemovalMethod.innoUninstaller,
      );
    });

    test('a portable copy uses the shipped script', () {
      expect(
        AppRemover.methodFor(
          kind: InstallKind.portable,
          uninstallerPresent: false,
          scriptPresent: true,
        ),
        AppRemovalMethod.portableScript,
      );
    });

    test('a package-manager copy is never removed from here', () {
      expect(
        AppRemover.methodFor(
          kind: InstallKind.managed,
          uninstallerPresent: true,
          scriptPresent: true,
        ),
        AppRemovalMethod.unsupported,
      );
    });

    test('without an uninstaller or a script there is nothing to run', () {
      expect(
        AppRemover.methodFor(
          kind: InstallKind.portable,
          uninstallerPresent: false,
          scriptPresent: false,
        ),
        AppRemovalMethod.unsupported,
      );
    });
  });

  group('building the command', () {
    test('the inno uninstaller runs silently', () {
      final command = AppRemover.commandFor(
        method: AppRemovalMethod.innoUninstaller,
        installDir: installDir,
        pid: 42,
        scriptPath: '',
      )!;

      expect(command.executable, endsWith(UpdateService.uninstallerName));
      expect(command.arguments, ['/SILENT', '/NORESTART']);
    });

    test('the script is told which process to wait for', () {
      final command = AppRemover.commandFor(
        method: AppRemovalMethod.portableScript,
        installDir: installDir,
        pid: 42,
        scriptPath: r'C:\Temp\uninstall.ps1',
      )!;

      expect(command.executable, 'powershell');
      expect(command.arguments, containsAllInOrder(['-WaitForPid', '42']));
      expect(command.arguments, containsAllInOrder(['-File', r'C:\Temp\uninstall.ps1']));
      // Unsigned script, so the default policy would refuse to run it.
      expect(command.arguments, containsAllInOrder(['-ExecutionPolicy', 'Bypass']));
    });

    test('keeping the library is only passed alongside removing app data', () {
      AppRemovalCommand build({required bool appData, required bool keep}) =>
          AppRemover.commandFor(
            method: AppRemovalMethod.portableScript,
            installDir: installDir,
            pid: 1,
            scriptPath: 'x.ps1',
            removeAppData: appData,
            keepLibrary: keep,
          )!;

      expect(build(appData: true, keep: true).arguments, contains('-KeepLibrary'));
      expect(
        build(appData: false, keep: true).arguments,
        isNot(contains('-KeepLibrary')),
      );
      expect(
        build(appData: false, keep: true).arguments,
        isNot(contains('-RemoveAppData')),
      );
    });

    test('an unsupported install has no command', () {
      expect(
        AppRemover.commandFor(
          method: AppRemovalMethod.unsupported,
          installDir: installDir,
          pid: 1,
          scriptPath: 'x',
        ),
        isNull,
      );
    });
  });
}
