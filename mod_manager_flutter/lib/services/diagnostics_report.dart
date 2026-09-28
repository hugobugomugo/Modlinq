import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_version.dart';
import '../games/deadlock/deadlock_gameinfo.dart';
import 'app_log.dart';
import 'config_service.dart';
import 'defender_exclusions.dart';
import 'integrity_service.dart';
import 'nte_game_detection.dart';
import 'nte_loader_service.dart';
import 'nte_mod_manager.dart';
import 'update_service.dart';

/// Builds one text file that answers "what does this install actually look
/// like" without another round of questions.
///
/// Every section is guarded on its own: a broken game path must still leave
/// the config and the log readable, because a partial report sent once beats
/// a perfect report that needs three more messages to obtain.
class DiagnosticsReport {
  /// Directory listings stop here. A library of a few hundred mods is worth
  /// seeing; the full tree of one is not.
  static const int listingLimit = 200;

  final ConfigService config;
  final IntegrityService integrity;
  final DefenderExclusions defender;

  /// The log tail to append. Injected so tests do not need a log file.
  final String Function() logTail;

  final DateTime Function() now;

  DiagnosticsReport({
    required this.config,
    IntegrityService? integrity,
    DefenderExclusions? defender,
    String Function()? logTail,
    DateTime Function()? now,
  }) : integrity =
           integrity ??
           IntegrityService(installDir: UpdateService.installDir()),
       defender = defender ?? DefenderExclusions(),
       logTail = logTail ?? (() => AppLog.recentAsText()),
       now = now ?? DateTime.now;

  Future<String> build() async {
    final out = StringBuffer();

    await _section(out, 'modlinq', _environment);
    await _section(out, 'bundle', _bundle);
    await _section(out, 'defender', _defender);
    await _section(out, 'config', _config);
    await _section(out, 'nte', _nte);
    await _section(out, 'deadlock', _deadlock);
    await _section(out, 'zzz / wuwa', _symlinkGames);
    await _section(out, 'log', (out) async => out.writeln(logTail()));

    return out.toString();
  }

  /// Writes the report next to the log file and returns its path.
  Future<File> writeToLogFolder() async {
    final stamp = now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .split('T')
        .join('-')
        .substring(0, 19);

    final file = File(
      p.join(AppLog.directoryPath, 'modlinq-diagnostics-$stamp.txt'),
    );
    file.parent.createSync(recursive: true);
    await file.writeAsString(await build());

    return file;
  }

  Future<void> _section(
    StringBuffer out,
    String title,
    Future<void> Function(StringBuffer out) body,
  ) async {
    out.writeln('== $title ==');
    try {
      await body(out);
    } catch (e, stack) {
      out.writeln('!! section failed: $e');
      out.writeln(stack.toString().split('\n').take(3).join('\n'));
    }
    out.writeln();
  }

  Future<void> _environment(StringBuffer out) async {
    out.writeln('version:   $appVersion');
    out.writeln(
      'platform:  ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}',
    );
    out.writeln('locale:    ${Platform.localeName}');
    out.writeln('generated: ${now().toIso8601String()}');
    out.writeln('install:   ${UpdateService.installDir().path}');
    out.writeln('kind:      ${(await UpdateService.detectInstallKind()).name}');
    out.writeln('test channel: ${config.testChannel}');
    out.writeln('config file:  ${config.debugConfigFilePath}');
    out.writeln('log file:     ${AppLog.filePath}');
  }

  /// The files antivirus removes, checked rather than assumed.
  Future<void> _bundle(StringBuffer out) async {
    final report = await integrity.check();
    out.writeln(report.healthy ? 'intact' : 'DAMAGED');

    for (final file in report.files) {
      out.writeln(
        '${file.state.name.padRight(8)} '
        '${file.expected.bytes.toString().padLeft(9)} b  ${file.assetKey}',
      );
    }
  }

  Future<void> _defender(StringBuffer out) async {
    if (!defender.supported) {
      out.writeln('not applicable on ${Platform.operatingSystem}');
      return;
    }

    final needed = DefenderExclusions.pathsFor(
      installDir: UpdateService.installDir().path,
      appDataDir: p.dirname(AppLog.directoryPath),
      nteGamePath: config.nteGamePath,
    );
    final missing = await defender.missing(needed);

    out.writeln(missing.isEmpty ? 'all needed paths excluded' : 'INCOMPLETE');
    for (final path in needed) {
      out.writeln('${missing.contains(path) ? 'MISSING ' : 'ok      '}$path');
    }
  }

  Future<void> _config(StringBuffer out) async {
    final snapshot = config.debugSnapshot();
    final keys = snapshot.keys.toList()..sort();

    for (final key in keys) {
      final value = snapshot[key];
      out.writeln('$key = ${value is List ? jsonEncode(value) : value}');
    }
  }

  Future<void> _nte(StringBuffer out) async {
    final gamePath = config.nteGamePath;
    out.writeln('game path: ${gamePath ?? '(not set)'}');
    if (gamePath == null || gamePath.isEmpty) return;

    final install = NteGameDetection.validate(gamePath);
    out.writeln('detected:  valid=${install.valid} edition=${install.edition.key}');

    final loader = NteLoaderService.fromConfig(config);
    if (loader == null) {
      out.writeln('loader:    no service (folder not a valid install)');
    } else {
      final status = loader.status;
      out.writeln('loader:    valid=${status.valid} dir=${status.loaderDir}');
      out.writeln(
        '           asi=${status.asiFound} cutils=${status.cutilsFound} '
        'proxy=${status.proxyFound} ${status.proxyNames.join(',')}',
      );
      out.writeln(
        '           missing=${status.missingFiles.isEmpty ? '-' : status.missingFiles.join(',')}',
      );
      _listDir(out, 'Binaries/Win64', status.loaderDir);
    }

    final manager = NteModManager.fromConfig(config);
    if (manager == null) return;

    out.writeln('library:   ${manager.library.rootPath}');
    _listDir(out, '~mods', manager.installer.pakTarget);

    // The line that decides most reports: what the app believes is on, versus
    // what is actually in the game folder.
    final mods = manager.listMods();
    final installed = mods.where((m) => m.enabled).map((m) => m.name).toSet();
    final intent = config.nteEnabledMods.toSet();

    out.writeln('enabled intent:    ${intent.length}');
    out.writeln('installed on disk: ${installed.length}');
    out.writeln(
      'intent not installed: ${_or(intent.difference(installed).toList())}',
    );
    out.writeln(
      'installed not in intent: ${_or(installed.difference(intent).toList())}',
    );
  }

  Future<void> _deadlock(StringBuffer out) async {
    final gamePath = config.deadlockGamePath;
    out.writeln('game path: ${gamePath ?? '(not set)'}');
    if (gamePath == null || gamePath.isEmpty) return;

    final gameinfo = DeadlockGameinfo(gamePath);
    out.writeln('gameinfo.gi: exists=${gameinfo.exists} path=${gameinfo.path}');
    out.writeln('library:     ${config.deadlockLibraryPath ?? '(default)'}');
    out.writeln('slots:       ${jsonEncode(config.deadlockSlots)}');
  }

  /// ZZZ and Wuthering Waves install through symlinks, so the interesting
  /// question is how many of the entries in the game folder are links.
  Future<void> _symlinkGames(StringBuffer out) async {
    for (final (name, mods, save) in [
      ('zzz', config.zzzModsPath, config.zzzSaveModsPath),
      ('wuwa', config.wwModsPath, config.wwSaveModsPath),
    ]) {
      out.writeln('$name mods path: ${mods ?? '(not set)'}');
      out.writeln('$name game path: ${save ?? '(not set)'}');

      if (save == null || save.isEmpty) continue;
      final dir = Directory(save);
      if (!dir.existsSync()) {
        out.writeln('$name game path does not exist');
        continue;
      }

      final entries = dir.listSync(followLinks: false);
      final links = entries.whereType<Link>().length;
      out.writeln('$name entries: ${entries.length}, of which links: $links');
    }
  }

  void _listDir(StringBuffer out, String label, String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      out.writeln('$label: missing ($path)');
      return;
    }

    final entries = dir.listSync(recursive: true, followLinks: false).toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    out.writeln('$label: ${entries.length} entries ($path)');
    for (final entry in entries.take(listingLimit)) {
      final relative = p.relative(entry.path, from: path);
      final size = entry is File ? '${entry.lengthSync()}' : 'dir';
      out.writeln('  ${size.padLeft(10)}  $relative');
    }
    if (entries.length > listingLimit) {
      out.writeln('  ... ${entries.length - listingLimit} more');
    }
  }

  static String _or(List<String> values) =>
      values.isEmpty ? '-' : values.join(', ');
}
