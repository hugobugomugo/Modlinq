import 'dart:io';
import 'package:path/path.dart' as path;

/// Helper class to get correct paths for assets depending on the environment
class PathHelper {
  static String? _modImagesPath;
  static String? _appDataPath;

  /// Get the path for application data directory
  /// Platform-aware: uses APPDATA on Windows, XDG on Linux
  static String getAppDataPath() {
    if (_appDataPath != null) {
      return _appDataPath!;
    }

    if (Platform.isWindows) {
      // Windows: %APPDATA%\zzz-mod-manager
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        _appDataPath = path.join(appData, 'zzz-mod-manager');
      } else {
        // Fallback на USERPROFILE\AppData\Roaming
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          _appDataPath = path.join(userProfile, 'AppData', 'Roaming', 'zzz-mod-manager');
        } else {
          throw Exception('Cannot find Windows user directory');
        }
      }
    } else {
      // Linux: ~/.local/share/zzz-mod-manager
      final homeDir = Platform.environment['HOME'];
      if (homeDir != null) {
        final xdgDataHome = Platform.environment['XDG_DATA_HOME'] ?? 
                            path.join(homeDir, '.local', 'share');
        _appDataPath = path.join(xdgDataHome, 'zzz-mod-manager');
      } else {
        throw Exception('Cannot find Linux home directory');
      }
    }

    return _appDataPath!;
  }

  /// Get the path for mod_images directory for a specific game.
  /// Defaults to 'zzz' for backward compatibility.
  /// Paths:
  ///   Windows: %APPDATA%\zzz-mod-manager\mod_images[_ww]
  ///   Linux: ~/.local/share/zzz-mod-manager/mod_images[_ww]
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
