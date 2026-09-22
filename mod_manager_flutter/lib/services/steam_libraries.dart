import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds Steam libraries and the game folders inside them.
///
/// Every supported game so far ships through Steam, so this lives outside any
/// single game: NTE and Deadlock both use it to answer "where is it installed"
/// without repeating the library-walking logic.
class SteamLibraries {
  const SteamLibraries._();

  static const List<String> _windowsLibraryFolderNames = ['Steam', 'SteamLibrary'];

  /// All `steamapps/common` directories across every library.
  static List<String> commons({Iterable<String>? steamRoots}) {
    final seen = <String>{};
    final commons = <String>[];

    for (final lib in libraryRoots(steamRoots: steamRoots)) {
      final common = p.join(lib, 'steamapps', 'common');
      if (!Directory(common).existsSync()) continue;
      if (seen.add(_canonical(common))) commons.add(common);
    }

    return commons;
  }

  /// Library roots, including the extra ones listed in `libraryfolders.vdf`.
  static List<String> libraryRoots({Iterable<String>? steamRoots}) {
    final roots = <String>[];

    for (final root in steamRoots ?? installRoots()) {
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

  /// Where Steam itself may be installed, per platform.
  static List<String> installRoots() {
    if (Platform.isWindows) return windowsInstallRoots();

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];

    return [
      p.join(home, '.steam', 'steam'),
      p.join(home, '.local', 'share', 'Steam'),
    ];
  }

  static List<String> windowsInstallRoots() {
    final roots = <String>[];

    void add(String? dir) {
      if (dir == null || dir.isEmpty) return;
      if (!roots.any((existing) => existing.toLowerCase() == dir.toLowerCase())) {
        roots.add(dir);
      }
    }

    add(steamPathFromRegistry());

    for (final variable in ['ProgramFiles(x86)', 'ProgramFiles']) {
      final base = Platform.environment[variable];
      if (base != null && base.isNotEmpty) add(p.join(base, 'Steam'));
    }

    // A second library on another drive is how Steam users deal with a full
    // system drive, and nothing registers it anywhere this app can read.
    for (final drive in windowsDriveRoots()) {
      for (final name in _windowsLibraryFolderNames) {
        add(p.join(drive, name));
      }
    }

    return roots;
  }

  /// Steam's own install path, as Steam records it for the current user.
  static String? steamPathFromRegistry() {
    if (!Platform.isWindows) return null;

    try {
      final result = Process.runSync('reg', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'SteamPath',
      ]);
      if (result.exitCode != 0) return null;

      final match = RegExp(
        r'SteamPath\s+REG_SZ\s+(.+)',
      ).firstMatch(result.stdout.toString());

      // Steam writes this value with forward slashes.
      return match?.group(1)?.trim().replaceAll('/', '\\');
    } catch (_) {
      return null; // reg.exe missing or blocked
    }
  }

  static List<String> windowsDriveRoots() {
    final drives = <String>[];

    for (var letter = 'C'.codeUnitAt(0); letter <= 'Z'.codeUnitAt(0); letter++) {
      final root = '${String.fromCharCode(letter)}:\\';
      if (Directory(root).existsSync()) drives.add(root);
    }

    return drives;
  }

  /// `steamapps/common/<installDir>` across all libraries, first hit wins.
  static String? findGameDir(String installDir, {Iterable<String>? steamRoots}) {
    for (final common in commons(steamRoots: steamRoots)) {
      final candidate = p.join(common, installDir);
      if (Directory(candidate).existsSync()) return candidate;
    }

    return null;
  }

  /// All `steamapps/compatdata/<id>/pfx` Proton prefixes.
  static List<String> protonPrefixes({Iterable<String>? steamRoots}) {
    final seen = <String>{};
    final prefixes = <String>[];

    for (final lib in libraryRoots(steamRoots: steamRoots)) {
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

  /// Extracts the value from a VDF line shaped like `"key"\t\t"value"`.
  static String? vdfValue(String line, String key) {
    final quotedKey = '"$key"';
    if (!line.startsWith(quotedKey)) return null;

    final rest = line.substring(quotedKey.length).trim();
    if (rest.length >= 2 && rest.startsWith('"') && rest.endsWith('"')) {
      // Windows paths are stored escaped: "D:\\SteamLibrary".
      return rest
          .substring(1, rest.length - 1)
          .replaceAll(r'\"', '"')
          .replaceAll(r'\\', '\\');
    }
    return null;
  }

  /// Reads `appmanifest_*.acf` files to find the app id whose `installdir`
  /// matches [installDir].
  static String? findAppId(String steamappsPath, String installDir) {
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
