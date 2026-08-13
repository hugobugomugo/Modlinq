import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/nte_mod.dart';

/// Installs and removes NTE mods in the game folder.
///
/// `.pak` content goes into `Content/Paks/~mods`, optionally inside a category
/// subfolder. `.asi` plugins go next to the game binary. The library copy is
/// never touched, so disabling only ever removes generated files.
class NteModInstaller {
  final String gameRoot;

  NteModInstaller(this.gameRoot);

  String get pakTarget =>
      p.join(gameRoot, 'Client', 'WindowsNoEditor', 'HT', 'Content', 'Paks', '~mods');

  String get asiTarget =>
      p.join(gameRoot, 'Client', 'WindowsNoEditor', 'HT', 'Binaries', 'Win64');

  /// Windows reports an open handle as a sharing violation. Other platforms do
  /// not lock files this way, so nothing is ever classified as locked there.
  static bool isLockedError(Object error) {
    if (error is! FileSystemException) return false;
    final code = error.osError?.errorCode;
    return Platform.isWindows && (code == 32 || code == 33);
  }

  /// Enables [mod], replacing any copy already installed elsewhere.
  void enable(NteMod mod) {
    if (!mod.isInstallable) {
      throw StateError('Mod "${mod.name}" has no .pak or .asi files to install');
    }

    if (mod.isPak) {
      // Remove stale copies first so a category change cannot leave duplicates.
      _removePakMod(mod.name);

      final destination = _pakDirFor(mod);
      Directory(destination).createSync(recursive: true);

      for (final file in mod.files) {
        final relative = p.relative(file, from: mod.dirPath);
        _copyFile(file, p.join(destination, relative));
      }
    }

    if (mod.isAsi) {
      for (final file in mod.files) {
        final relative = p.relative(file, from: mod.dirPath);
        _copyFile(file, p.join(asiTarget, relative));
      }
    }
  }

  /// Removes [mod]'s installed files from the game folder.
  void disable(NteMod mod) {
    if (mod.isPak) _removePakMod(mod.name);

    if (mod.isAsi) {
      for (final file in mod.files) {
        final relative = p.relative(file, from: mod.dirPath);
        final installed = File(p.join(asiTarget, relative));
        if (installed.existsSync()) installed.deleteSync();
      }
    }
  }

  /// Whether every file of [mod] is present in the game folder.
  bool isEnabled(NteMod mod) {
    if (!mod.isInstallable) return false;

    if (mod.isPak) {
      final installedDir = _findInstalledPakDir(mod.name);
      if (installedDir == null) return false;

      final allPresent = mod.files.every((file) {
        final relative = p.relative(file, from: mod.dirPath);
        return File(p.join(installedDir, relative)).existsSync();
      });
      if (!allPresent) return false;
    }

    if (mod.isAsi) {
      final allPresent = mod.files.every((file) {
        final relative = p.relative(file, from: mod.dirPath);
        return File(p.join(asiTarget, relative)).existsSync();
      });
      if (!allPresent) return false;
    }

    return true;
  }

  /// The category a mod is currently installed under, if any.
  String? installedCategoryOf(String modName) {
    final dir = _findInstalledPakDir(modName);
    if (dir == null) return null;

    final parent = p.dirname(dir);
    return p.equals(parent, pakTarget) ? null : p.basename(parent);
  }

  /// Applies the desired enabled state for [mods], collecting per-mod failures
  /// instead of aborting, so one locked mod cannot block the rest.
  NteApplyResult apply(Iterable<NteMod> mods, Set<String> enabledNames) {
    final applied = <String>[];
    final locked = <String>[];
    final errors = <String, String>{};

    for (final mod in mods) {
      if (!mod.isInstallable) continue;

      final shouldEnable = enabledNames.contains(mod.name);
      if (isEnabled(mod) == shouldEnable) continue;

      try {
        shouldEnable ? enable(mod) : disable(mod);
        applied.add(mod.name);
      } catch (e) {
        if (isLockedError(e)) {
          locked.add(mod.name);
        } else {
          errors[mod.name] = e.toString();
        }
      }
    }

    return NteApplyResult(applied: applied, locked: locked, errors: errors);
  }

  String _pakDirFor(NteMod mod) {
    final category = mod.category;
    return category == null || category.isEmpty
        ? p.join(pakTarget, mod.name)
        : p.join(pakTarget, category, mod.name);
  }

  /// Looks for an installed mod folder at the root of `~mods` and one level
  /// down, which is where category subfolders put it.
  String? _findInstalledPakDir(String modName) {
    final atRoot = p.join(pakTarget, modName);
    if (Directory(atRoot).existsSync()) return atRoot;

    for (final category in _categoryDirs()) {
      final inCategory = p.join(category, modName);
      if (Directory(inCategory).existsSync()) return inCategory;
    }

    return null;
  }

  void _removePakMod(String modName) {
    final atRoot = Directory(p.join(pakTarget, modName));
    if (atRoot.existsSync()) atRoot.deleteSync(recursive: true);

    for (final category in _categoryDirs()) {
      final inCategory = Directory(p.join(category, modName));
      if (inCategory.existsSync()) inCategory.deleteSync(recursive: true);
    }
  }

  List<String> _categoryDirs() {
    final root = Directory(pakTarget);
    if (!root.existsSync()) return const [];

    try {
      return root.listSync().whereType<Directory>().map((d) => d.path).toList();
    } catch (_) {
      return const [];
    }
  }

  void _copyFile(String source, String destination) {
    Directory(p.dirname(destination)).createSync(recursive: true);
    File(source).copySync(destination);
  }
}
