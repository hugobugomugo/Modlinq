import 'dart:io';

import 'package:path/path.dart' as p;

/// Which regional build of Neverness to Everness an install folder contains.
enum NteEdition { global, cn, tw, unknown }

extension NteEditionX on NteEdition {
  String get key => switch (this) {
    NteEdition.global => 'global',
    NteEdition.cn => 'cn',
    NteEdition.tw => 'tw',
    NteEdition.unknown => 'unknown',
  };

  /// Launcher executable that starts this edition, relative to the game root.
  String? get launcherExe => switch (this) {
    NteEdition.global => 'NTEGlobalLauncher.exe',
    NteEdition.cn => 'NTELauncher.exe',
    NteEdition.tw => 'NTETWLauncher.exe',
    NteEdition.unknown => null,
  };
}

/// Result of inspecting a candidate Neverness to Everness install folder.
class NteInstall {
  final bool valid;
  final String path;
  final NteEdition edition;

  /// Wine or Proton prefix this install runs under, when detected on Linux.
  final String? compatPrefix;

  const NteInstall({
    required this.valid,
    required this.path,
    required this.edition,
    this.compatPrefix,
  });

  const NteInstall.notFound()
    : valid = false,
      path = '',
      edition = NteEdition.unknown,
      compatPrefix = null;

  /// Directory that `.pak` mods are copied into.
  String get paksModsPath =>
      p.join(path, 'Client', 'WindowsNoEditor', 'HT', 'Content', 'Paks', '~mods');

  /// Directory that `.asi` mods and the loader are installed into.
  String get binariesPath =>
      p.join(path, 'Client', 'WindowsNoEditor', 'HT', 'Binaries', 'Win64');

  NteInstall copyWith({String? compatPrefix}) => NteInstall(
    valid: valid,
    path: path,
    edition: edition,
    compatPrefix: compatPrefix ?? this.compatPrefix,
  );
}

/// Locates and validates Neverness to Everness installs.
///
/// Ported from NTEMM's `src-tauri/src/game/{game,steam}.rs`. Windows uses the
/// default install location; Linux scans Steam libraries and matches the
/// install against its Proton prefix.
class NteGameDetection {
  static const String windowsDefaultPath = r'C:\Program Files\Neverness To Everness';

  /// Checks whether [gamePath] is a valid install and which edition it is.
  static NteInstall validate(String gamePath) {
    final dir = Directory(gamePath);
    if (gamePath.isEmpty || !dir.existsSync()) {
      return const NteInstall.notFound();
    }

    // Files shared by every edition. Without these the folder is not a game.
    final win64 = p.join(gamePath, 'Client', 'WindowsNoEditor', 'HT', 'Binaries', 'Win64');
    final paks = p.join(gamePath, 'Client', 'WindowsNoEditor', 'HT', 'Content', 'Paks');

    final sharedFilesValid =
        File(p.join(win64, 'HTGame.exe')).existsSync() &&
        File(p.join(paks, 'global.ucas')).existsSync() &&
        File(p.join(paks, 'global.utoc')).existsSync();

    if (!sharedFilesValid) {
      return NteInstall(valid: false, path: gamePath, edition: NteEdition.unknown);
    }

    final edition = _detectEdition(gamePath);

    return NteInstall(
      valid: edition != NteEdition.unknown,
      path: gamePath,
      edition: edition,
    );
  }

  /// Each edition ships a root launcher plus a subfolder with three binaries.
  static NteEdition _detectEdition(String gamePath) {
    const layouts = <NteEdition, (String, String, List<String>)>{
      NteEdition.global: (
        'NTEGlobalLauncher.exe',
        'NTEGlobal',
        ['NTEGlobalGame.exe', 'NTEGlobalLauncher.exe', 'NTEGlobalUpdate.exe'],
      ),
      NteEdition.cn: (
        'NTELauncher.exe',
        'NTELauncher',
        ['NTEGame.exe', 'NTELauncher.exe', 'NTEUpdate.exe'],
      ),
      NteEdition.tw: (
        'NTETWLauncher.exe',
        'NTETW',
        ['NTETWGame.exe', 'NTETWLauncher.exe', 'NTETWUpdate.exe'],
      ),
    };

    for (final entry in layouts.entries) {
      final (rootLauncher, subfolder, binaries) = entry.value;

      if (!File(p.join(gamePath, rootLauncher)).existsSync()) continue;

      final subdir = p.join(gamePath, subfolder);
      if (!Directory(subdir).existsSync()) continue;

      final allBinariesPresent = binaries.every(
        (exe) => File(p.join(subdir, exe)).existsSync(),
      );
      if (allBinariesPresent) return entry.key;
    }

    return NteEdition.unknown;
  }

  /// Searches the usual locations for an install. Returns an invalid
  /// [NteInstall] when nothing is found, so callers can prompt for a path.
  static NteInstall autoDetect() {
    if (Platform.isWindows) {
      return validate(windowsDefaultPath);
    }

    for (final candidate in linuxCandidatePaths()) {
      final check = validate(candidate);
      if (check.valid) {
        return check.copyWith(compatPrefix: findCompatPrefixFor(candidate));
      }
    }

    return const NteInstall.notFound();
  }

  /// Folders that may contain a game install, in search order.
  ///
  /// Covers Steam libraries plus the launcher-agnostic Wine layouts used by
  /// Lutris, Heroic, Bottles and manual prefixes, where the game lives outside
  /// any Steam library.
  static List<String> linuxCandidatePaths() {
    final candidates = <String>[];
    final seen = <String>{};

    void add(String dir) {
      if (seen.add(dir)) candidates.add(dir);
    }

    for (final common in steamLibraryCommons()) {
      _subdirectoriesOf(common).forEach(add);
    }

    // Games added to Steam as non-Steam shortcuts install into their Proton
    // prefix rather than into a Steam library.
    for (final pfx in steamProtonPrefixes()) {
      _windowsInstallDirsIn(pfx).forEach(add);
    }

    for (final root in _winePrefixRoots()) {
      for (final prefix in _subdirectoriesOf(root)) {
        // The game may sit directly in the folder, as launcher installers do.
        add(prefix);
        // Or inside the prefix's virtual C: drive.
        _windowsInstallDirsIn(prefix).forEach(add);
      }
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      _windowsInstallDirsIn(p.join(home, '.wine')).forEach(add);
    }

    return candidates;
  }

  /// Folders whose children are Wine prefixes or game directories.
  static List<String> _winePrefixRoots() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];

    return [
      p.join(home, 'Games'),
      p.join(home, 'Games', 'Heroic', 'Prefixes'),
      p.join(home, '.local', 'share', 'wineprefixes'),
      p.join(home, '.var', 'app', 'com.usebottles.bottles', 'data', 'bottles', 'bottles'),
    ];
  }

  /// Install directories inside a Wine prefix's virtual C: drive.
  static List<String> _windowsInstallDirsIn(String prefix) {
    final driveC = p.join(prefix, 'drive_c');
    if (!Directory(driveC).existsSync()) return const [];

    return [
      ..._subdirectoriesOf(p.join(driveC, 'Program Files')),
      ..._subdirectoriesOf(p.join(driveC, 'Program Files (x86)')),
      ..._subdirectoriesOf(driveC),
    ];
  }

  /// Subdirectories of [dir], following symlinks so that linked game folders
  /// (a common way to expose a game living inside a prefix) are included.
  static List<String> _subdirectoriesOf(String dir) {
    final directory = Directory(dir);
    if (!directory.existsSync()) return const [];

    try {
      return directory
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path)
          .toList();
    } catch (_) {
      return const []; // unreadable directory
    }
  }

  /// Extracts the value from a VDF line shaped like `"key"\t\t"value"`.
  static String? vdfValue(String line, String key) {
    final quotedKey = '"$key"';
    if (!line.startsWith(quotedKey)) return null;

    final rest = line.substring(quotedKey.length).trim();
    if (rest.length >= 2 && rest.startsWith('"') && rest.endsWith('"')) {
      return rest.substring(1, rest.length - 1);
    }
    return null;
  }

  static List<String> _steamRoots() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];
    return [
      p.join(home, '.steam', 'steam'),
      p.join(home, '.local', 'share', 'Steam'),
    ];
  }

  /// Every Steam library root, including those listed in `libraryfolders.vdf`.
  static List<String> _steamLibraryRoots() {
    final roots = <String>[];

    for (final root in _steamRoots()) {
      if (!Directory(root).existsSync()) continue;
      roots.add(root);

      final vdf = File(p.join(root, 'steamapps', 'libraryfolders.vdf'));
      if (!vdf.existsSync()) continue;

      for (final line in vdf.readAsLinesSync()) {
        final libPath = vdfValue(line.trim(), 'path');
        if (libPath != null && libPath.isNotEmpty) roots.add(libPath);
      }
    }

    return roots;
  }

  /// All `steamapps/common` directories across every Steam library.
  static List<String> steamLibraryCommons() {
    final seen = <String>{};
    final commons = <String>[];

    for (final lib in _steamLibraryRoots()) {
      final common = p.join(lib, 'steamapps', 'common');
      if (!Directory(common).existsSync()) continue;
      if (seen.add(_canonical(common))) commons.add(common);
    }

    return commons;
  }

  /// All `steamapps/compatdata/<id>/pfx` Proton prefixes.
  static List<String> steamProtonPrefixes() {
    final seen = <String>{};
    final prefixes = <String>[];

    for (final lib in _steamLibraryRoots()) {
      final compatdata = Directory(p.join(lib, 'steamapps', 'compatdata'));
      if (!compatdata.existsSync()) continue;

      for (final entry in compatdata.listSync().whereType<Directory>()) {
        final pfx = p.join(entry.path, 'pfx');
        if (!Directory(pfx).existsSync()) continue;
        if (seen.add(_canonical(pfx))) prefixes.add(pfx);
      }
    }

    return prefixes;
  }

  /// Resolves the Wine or Proton prefix an install runs under.
  ///
  /// A path inside a `drive_c` belongs to the prefix containing it. Otherwise
  /// the install is assumed to be a Steam game, whose Proton prefix is keyed by
  /// the same app id as its `steamapps/common` folder.
  static String? findCompatPrefixFor(String gamePath) {
    final winePrefix = _winePrefixContaining(gamePath);
    if (winePrefix != null) return winePrefix;

    // steamapps/common/<GameDir> -> steamapps/
    final steamapps = p.dirname(p.dirname(gamePath));
    final installDir = p.basename(gamePath);

    final appId = findSteamAppId(steamapps, installDir);
    if (appId == null) return null;

    final pfx = p.join(steamapps, 'compatdata', appId, 'pfx');
    return Directory(pfx).existsSync() ? pfx : null;
  }

  /// Walks up from [gamePath] to the prefix root that owns its `drive_c`.
  static String? _winePrefixContaining(String gamePath) {
    var current = p.normalize(gamePath);

    while (true) {
      final parent = p.dirname(current);
      if (parent == current) return null; // reached the filesystem root

      if (p.basename(current) == 'drive_c') return parent;
      current = parent;
    }
  }

  /// Reads `appmanifest_*.acf` files to find the app id whose `installdir`
  /// matches [installDir].
  static String? findSteamAppId(String steamappsPath, String installDir) {
    final steamapps = Directory(steamappsPath);
    if (!steamapps.existsSync()) return null;

    for (final file in steamapps.listSync().whereType<File>()) {
      final name = p.basename(file.path);
      if (!name.startsWith('appmanifest_') || !name.endsWith('.acf')) continue;

      String? appId;
      var dirMatches = false;

      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        appId ??= vdfValue(trimmed, 'appid');

        final dir = vdfValue(trimmed, 'installdir');
        if (dir != null && dir.toLowerCase() == installDir.toLowerCase()) {
          dirMatches = true;
        }
      }

      if (dirMatches && appId != null) return appId;
    }

    return null;
  }

  static String _canonical(String path) {
    try {
      return Directory(path).resolveSymbolicLinksSync();
    } catch (_) {
      return path;
    }
  }
}
