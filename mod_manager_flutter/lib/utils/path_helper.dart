import 'dart:io';
import 'package:path/path.dart' as path;

/// Helper class to get correct paths for assets depending on the environment
class PathHelper {
  static String? _modImagesPath;
  static String? _appDataPath;

  /// Folder name for application data.
  static const String appDataFolderName = 'modlinq';

  /// Folder used before the app was renamed from ZZZ Mod Manager.
  static const String legacyAppDataFolderName = 'zzz-mod-manager';

  /// Get the path for application data directory
  /// Platform-aware: uses APPDATA on Windows, XDG on Linux
  static String getAppDataPath() {
    if (_appDataPath != null) {
      return _appDataPath!;
    }

    final root = _appDataRoot();
    final current = path.join(root, appDataFolderName);

    _migrateLegacyAppData(path.join(root, legacyAppDataFolderName), current);
    _appDataPath = current;

    return _appDataPath!;
  }

  /// Directory that holds the app's data folder.
  static String _appDataRoot() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) return appData;

      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        return path.join(userProfile, 'AppData', 'Roaming');
      }
      throw Exception('Cannot find Windows user directory');
    }

    final homeDir = Platform.environment['HOME'];
    if (homeDir == null) {
      throw Exception('Cannot find Linux home directory');
    }

    return Platform.environment['XDG_DATA_HOME'] ??
        path.join(homeDir, '.local', 'share');
  }

  /// Moves data from the pre-rename folder, so settings and mod libraries
  /// survive the rename.
  ///
  /// This is a rename within one directory, so it costs nothing regardless of
  /// how large the mod library is. It runs only when the new folder does not
  /// exist yet, and a failure is not fatal: the app then starts on a fresh
  /// folder rather than refusing to launch.
  static void _migrateLegacyAppData(String legacyPath, String currentPath) {
    try {
      final legacy = Directory(legacyPath);
      if (!legacy.existsSync()) return;
      if (Directory(currentPath).existsSync()) return;

      legacy.renameSync(currentPath);
    } catch (e) {
      // Leaves the legacy folder untouched for a manual move.
    }
  }

  /// Get the path for mod_images directory for a specific game.
  /// Defaults to 'zzz' for backward compatibility.
  /// Paths:
  ///   Windows: %APPDATA%\modlinq\mod_images[_ww]
  ///   Linux: ~/.local/share/modlinq/mod_images[_ww]
  static String getModImagesPath({String game = 'zzz'}) {
    if (game == 'zzz' && _modImagesPath != null) {
      return _modImagesPath!;
    }

    try {
      final dirName = game == 'zzz' ? 'mod_images' : 'mod_images_$game';
      final result = path.join(getAppDataPath(), dirName);
      if (game == 'zzz') _modImagesPath = result;
      return result;
    } catch (e) {
      // Fallback for development (relative to current directory)
      final possiblePaths = [
        path.join(Directory.current.path, '..', 'assets', 'mod_images'),
        path.join(Directory.current.path, 'assets', 'mod_images'),
        path.join(Directory.current.path, '..', '..', 'assets', 'mod_images'),
      ];

      for (final possiblePath in possiblePaths) {
        final dir = Directory(possiblePath);
        if (dir.existsSync()) {
          if (game == 'zzz') _modImagesPath = possiblePath;
          return possiblePath;
        }
      }

      final fallback = path.join(Directory.current.path, '..', 'assets', 'mod_images');
      if (game == 'zzz') _modImagesPath = fallback;
      return fallback;
    }
  }

  /// Ensure the mod_images directory exists for a given game
  static Future<void> ensureModImagesDirectoryExists({String game = 'zzz'}) async {
    final dir = Directory(getModImagesPath(game: game));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Reset cached paths (useful for testing)
  static void resetCache() {
    _modImagesPath = null;
    _appDataPath = null;
  }
}
