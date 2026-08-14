import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/nte_mod.dart';
import 'nte_mod_library.dart';

/// Result of migrating a standalone NTEMM library.
class NteMmImportResult {
  final List<NteMod> imported;

  /// Mods left alone, keyed by folder name, with the reason.
  final Map<String, String> skipped;

  const NteMmImportResult({this.imported = const [], this.skipped = const {}});

  int get importedCount => imported.length;
  int get skippedCount => skipped.length;
}

/// Migrates mods from a standalone NTEMM install into this app's library.
///
/// NTEMM keeps each mod as a folder inside an `NTEMM_Mods` directory next to
/// its executable, which is the same shape this app uses, so migrating is a
/// copy per folder. The source is never modified.
class NteMmImporter {
  final NteModLibrary library;

  NteMmImporter(this.library);

  static const String storageFolderName = 'NTEMM_Mods';

  /// Locations that may hold an NTEMM library, most likely first.
  ///
  /// Covers installed copies as well as the build output folders used when
  /// running NTEMM from source.
  static List<String> candidateRoots() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return const [];

    final roots = <String>[
      p.join(home, 'project', 'NTEMM', 'src-tauri', 'target', 'release'),
      p.join(home, 'project', 'NTEMM', 'src-tauri', 'target', 'debug'),
    ];

    // Installed builds live inside a Wine prefix on Linux.
    for (final prefix in [
      p.join(home, '.wine'),
      p.join(home, 'Games', 'NTEMM'),
    ]) {
      roots.add(p.join(prefix, 'drive_c', 'Program Files', 'NTEMM'));
      roots.add(p.join(prefix, 'drive_c', 'Program Files (x86)', 'NTEMM'));
    }

    return roots
        .map((root) => p.join(root, storageFolderName))
        .where((path) => Directory(path).existsSync())
        .toList();
  }

  /// Mod folders inside an NTEMM library, sorted by name.
  static List<String> modFoldersIn(String ntemmLibraryPath) {
    final dir = Directory(ntemmLibraryPath);
    if (!dir.existsSync()) return const [];

    final folders = dir.listSync().whereType<Directory>().map((d) => d.path).toList();
    folders.sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
    return folders;
  }

  /// Copies every mod from [ntemmLibraryPath] that is not already present.
  ///
  /// [onProgress] reports the mod name and its 1-based position, so large
  /// libraries can show progress instead of appearing frozen.
  NteMmImportResult importFrom(
    String ntemmLibraryPath, {
    void Function(String modName, int index, int total)? onProgress,
  }) {
    final folders = modFoldersIn(ntemmLibraryPath);
    final imported = <NteMod>[];
    final skipped = <String, String>{};

    library.ensureExists();

    for (var i = 0; i < folders.length; i++) {
      final folder = folders[i];
      final name = p.basename(folder);
      onProgress?.call(name, i + 1, folders.length);

      if (library.findMod(name) != null) {
        skipped[name] = 'Already in the library';
        continue;
      }

      try {
        final mod = library.importDirectory(folder);
        if (mod == null) {
          skipped[name] = 'No .pak or .asi files found';
        } else {
          imported.add(mod);
        }
      } catch (e) {
        skipped[name] = e is StateError ? e.message : e.toString();
      }
    }

    return NteMmImportResult(imported: imported, skipped: skipped);
  }
}
