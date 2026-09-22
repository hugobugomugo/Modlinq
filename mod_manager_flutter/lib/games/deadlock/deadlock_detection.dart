import 'dart:io';

import 'package:path/path.dart' as p;

import '../../services/steam_libraries.dart';

/// A candidate Deadlock install folder, checked.
class DeadlockInstall {
  final bool valid;
  final String path;

  const DeadlockInstall({required this.valid, required this.path});

  const DeadlockInstall.notFound() : valid = false, path = '';

  /// Where `.vpk` mods are copied. Source 2 only reads this once
  /// `gameinfo.gi` lists it, which the loader patch takes care of.
  String get addonsPath => p.join(path, 'game', 'citadel', 'addons');

  String get gameinfoPath => p.join(path, 'game', 'citadel', 'gameinfo.gi');
}

/// Locates Deadlock. Steam is the only way to get the game, so a Steam
/// library walk plus a manual folder pick covers every case.
class DeadlockDetection {
  const DeadlockDetection._();

  /// Steam's folder name for the game, used to find it in a library.
  static const String steamInstallDir = 'Deadlock';

  static DeadlockInstall validate(String gamePath) {
    if (gamePath.isEmpty || !Directory(gamePath).existsSync()) {
      return const DeadlockInstall.notFound();
    }

    final gameinfo = File(p.join(gamePath, 'game', 'citadel', 'gameinfo.gi'));

    // The Windows binary is present on Linux too: the game runs under Proton,
    // so the install layout is the same either way.
    final binary = File(
      p.join(gamePath, 'game', 'bin', 'win64', 'deadlock.exe'),
    );

    final valid = gameinfo.existsSync() && binary.existsSync();
    return DeadlockInstall(valid: valid, path: gamePath);
  }

  static DeadlockInstall autoDetect({Iterable<String>? steamRoots}) {
    final dir = SteamLibraries.findGameDir(
      steamInstallDir,
      steamRoots: steamRoots,
    );
    if (dir == null) return const DeadlockInstall.notFound();

    return validate(dir);
  }
}
