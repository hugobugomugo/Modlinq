import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_log.dart';
import 'update_service.dart';

/// How this copy of Modlinq can be taken off the machine.
enum AppRemovalMethod {
  /// Hand over to the installer's own uninstaller.
  innoUninstaller,

  /// Run the shipped script, which waits for this process and deletes the
  /// folder it was running from.
  portableScript,

  /// Someone else owns these files: a package manager, or a folder this user
  /// cannot write. Removing them from here would only half work.
  unsupported,
}

/// What to launch, kept separate from launching it so the decision can be
/// tested without spawning anything.
class AppRemovalCommand {
  final String executable;
  final List<String> arguments;

  const AppRemovalCommand(this.executable, this.arguments);
}

/// Starts the removal of Modlinq itself.
///
/// A running executable cannot delete its own folder, so every path here ends
/// the same way: launch something detached that outlives this process, then
/// quit so the files are free.
class AppRemover {
  static const String scriptName = 'uninstall.ps1';

  static AppRemovalMethod methodFor({
    required InstallKind kind,
    required bool uninstallerPresent,
    required bool scriptPresent,
  }) {
    if (kind == InstallKind.managed) return AppRemovalMethod.unsupported;
    if (uninstallerPresent) return AppRemovalMethod.innoUninstaller;
    if (scriptPresent) return AppRemovalMethod.portableScript;

    return AppRemovalMethod.unsupported;
  }

  /// The command for [method]. Null when nothing can be launched.
  ///
  /// [scriptPath] is the copy in the temp folder: the shipped one lives in
  /// the folder being deleted, and PowerShell holding it open is exactly what
  /// makes a delete fail.
  static AppRemovalCommand? commandFor({
    required AppRemovalMethod method,
    required Directory installDir,
    required int pid,
    required String scriptPath,
    bool removeAppData = false,
    bool keepLibrary = false,
  }) => switch (method) {
    AppRemovalMethod.innoUninstaller => AppRemovalCommand(
      p.join(installDir.path, UpdateService.uninstallerName),
      const ['/SILENT', '/NORESTART'],
    ),
    AppRemovalMethod.portableScript => AppRemovalCommand('powershell', [
      '-NoProfile',
      // The script ships unsigned, so the default policy would refuse it.
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      scriptPath,
      '-WaitForPid',
      '$pid',
      '-AppDir',
      installDir.path,
      if (removeAppData) '-RemoveAppData',
      if (removeAppData && keepLibrary) '-KeepLibrary',
    ]),
    AppRemovalMethod.unsupported => null,
  };

  /// Copies the shipped script somewhere it will survive the folder it came
  /// from being deleted.
  static File stageScript(Directory installDir) {
    final source = File(p.join(installDir.path, scriptName));
    final target = File(
      p.join(Directory.systemTemp.createTempSync('modlinq-uninstall').path, scriptName),
    );

    source.copySync(target.path);
    return target;
  }

  /// Launches the removal and returns. The caller must exit straight after,
  /// so the files stop being held open.
  static Future<void> start({
    bool removeAppData = false,
    bool keepLibrary = false,
  }) async {
    final installDir = UpdateService.installDir();
    final kind = await UpdateService.detectInstallKind(dir: installDir);

    final method = methodFor(
      kind: kind,
      uninstallerPresent: File(
        p.join(installDir.path, UpdateService.uninstallerName),
      ).existsSync(),
      scriptPresent: File(p.join(installDir.path, scriptName)).existsSync(),
    );

    if (method == AppRemovalMethod.unsupported) {
      throw StateError(
        'This copy of Modlinq cannot remove itself: $kind. '
        'Use your package manager, or delete ${installDir.path} by hand.',
      );
    }

    final script = method == AppRemovalMethod.portableScript
        ? stageScript(installDir).path
        : '';

    final command = commandFor(
      method: method,
      installDir: installDir,
      pid: pid,
      scriptPath: script,
      removeAppData: removeAppData,
      keepLibrary: keepLibrary,
    )!;

    AppLog.warn(
      'Starting app removal via ${method.name}',
      details: '${command.executable} ${command.arguments.join(' ')}',
    );

    await Process.start(
      command.executable,
      command.arguments,
      mode: ProcessStartMode.detached,
    );
  }
}
