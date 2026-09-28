import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_log.dart';

/// Manages the Windows Defender exclusions the NTE mod loader needs.
///
/// `loader.asi` is structurally a DLL injector, so Defender removes it
/// generically — out of the game folder and out of Modlinq's own install
/// folder. Without an exclusion every repair is undone within minutes, which
/// is why this exists rather than only telling the user to do it by hand.
class DefenderExclusions {
  /// Runs PowerShell. Injected so the command can be asserted in tests.
  final Future<ProcessResult> Function(List<String> args) run;

  /// Only Windows has Defender. Elsewhere every call is a no-op rather than
  /// an error, so callers do not need a platform check of their own.
  final bool supported;

  DefenderExclusions({
    Future<ProcessResult> Function(List<String> args)? run,
    bool? supported,
  }) : run = run ?? _powershell,
       supported = supported ?? Platform.isWindows;

  static Future<ProcessResult> _powershell(List<String> args) =>
      Process.run('powershell', args);

  /// Folders that have to be excluded, in the order they matter.
  ///
  /// Deliberately narrow: the game's `Binaries/Win64` rather than the whole
  /// game, and Modlinq's own folders rather than a drive.
  static List<String> pathsFor({
    required String installDir,
    required String appDataDir,
    String? nteGamePath,
  }) => [
    installDir,
    appDataDir,
    if (nteGamePath != null && nteGamePath.isNotEmpty)
      // Windows semantics explicitly: Defender only exists there, and the
      // tests run on whatever the developer is using.
      p.windows.join(
        nteGamePath,
        'Client',
        'WindowsNoEditor',
        'HT',
        'Binaries',
        'Win64',
      ),
  ];

  /// Exclusions Defender currently holds. Empty when it cannot be asked,
  /// which is treated as "none known" rather than an error: the add is
  /// idempotent anyway.
  Future<Set<String>> current() async {
    if (!supported) return {};

    try {
      final result = await run(const [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        '(Get-MpPreference).ExclusionPath',
      ]);

      return result.stdout
          .toString()
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toSet();
    } catch (e) {
      AppLog.warn('Could not read Defender exclusions', details: '$e');
      return {};
    }
  }

  /// Which of [paths] Defender does not cover yet.
  ///
  /// Matching is case-insensitive and treats a parent exclusion as covering
  /// its children, because excluding a game folder also excludes what is in
  /// it and asking again would be noise.
  Future<List<String>> missing(List<String> paths) async {
    final existing = await current();
    if (existing.isEmpty) return List.of(paths);

    final normalised = existing.map(_normalise).toList();

    return paths.where((path) {
      final candidate = _normalise(path);
      return !normalised.any(
        (e) => candidate == e || p.windows.isWithin(e, candidate),
      );
    }).toList();
  }

  static String _normalise(String path) =>
      p.windows.normalize(path.replaceAll('/', r'\')).toLowerCase();

  /// Builds the elevated command. Separate from running it so the exact
  /// PowerShell can be asserted without a UAC prompt in a test.
  static List<String> addCommand(List<String> paths) =>
      _elevatedCommand('Add-MpPreference', paths);

  static List<String> removeCommand(List<String> paths) =>
      _elevatedCommand('Remove-MpPreference', paths);

  static List<String> _elevatedCommand(String cmdlet, List<String> paths) {
    // Each path is its own call: one bad path must not take the rest with it.
    final inner = paths
        .map((path) => "$cmdlet -ExclusionPath '${_psQuote(path)}'")
        .join('; ');

    return [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Start-Process -FilePath 'powershell' -Verb RunAs -Wait -ArgumentList "
          "'-NoProfile','-NonInteractive','-Command','${_psQuote(inner)}'",
    ];
  }

  /// Single quotes escape themselves inside PowerShell single-quoted strings.
  static String _psQuote(String value) => value.replaceAll("'", "''");

  Future<void> add(List<String> paths) => _apply(addCommand(paths), 'add');

  Future<void> remove(List<String> paths) =>
      _apply(removeCommand(paths), 'remove');

  Future<void> _apply(List<String> args, String what) async {
    if (!supported) {
      throw UnsupportedError('Defender exclusions are a Windows feature');
    }

    final result = await run(args);
    if (result.exitCode != 0) {
      throw ProcessException(
        'powershell',
        args,
        'Could not $what Defender exclusions: ${result.stderr}',
        result.exitCode,
      );
    }

    AppLog.warn('Defender exclusions changed ($what)', details: args.last);
  }
}
