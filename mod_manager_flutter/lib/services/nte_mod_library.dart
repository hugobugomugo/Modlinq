import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../models/nte_mod.dart';

/// Owns the app-managed folder that stores imported NTE mods.
///
/// Importing copies files in, so the user's original folders and archives are
/// left untouched and the library stays valid if those sources disappear.
class NteModLibrary {
  final String rootPath;

  NteModLibrary(this.rootPath);

  /// Files that live alongside a mod's payload but are never installed.
  static bool isHelperFile(String fileName) {
    final name = fileName.toLowerCase();
    if (name == 'icon.ico' || name == 'icon.png' || name == 'desktop.ini' || name == 'mod.json') {
      return true;
    }
    return isPreviewImage(fileName);
  }

  static bool isPreviewImage(String fileName) {
    final name = fileName.toLowerCase();
    const imageExtensions = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
    if (!imageExtensions.any(name.endsWith)) return false;

    // Icons are handled separately; everything else is a preview.
    return name != 'icon.png';
  }

  /// Archive types the importer can unpack without external tools.
  static bool isSupportedArchive(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.zip';
  }

  Directory get _root => Directory(rootPath);

  void ensureExists() {
    if (!_root.existsSync()) _root.createSync(recursive: true);
  }

  /// Every mod currently in the library, sorted by name.
  List<NteMod> listMods() {
    if (!_root.existsSync()) return const [];

    final mods = <NteMod>[];
    for (final dir in _root.listSync().whereType<Directory>()) {
      mods.add(_readMod(dir.path));
    }

    mods.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return mods;
  }

  NteMod? findMod(String name) {
    final dir = Directory(p.join(rootPath, name));
    return dir.existsSync() ? _readMod(dir.path) : null;
  }

  NteMod _readMod(String dirPath) => NteMod(
    name: p.basename(dirPath),
    dirPath: dirPath,
    files: payloadFilesIn(dirPath),
  );

  /// Installable files inside [dirPath], recursively.
  static List<String> payloadFilesIn(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];

    final files = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (isHelperFile(p.basename(entity.path))) continue;
      files.add(entity.path);
    }

    files.sort();
    return files;
  }

  /// Whether [dirPath] holds anything the game can actually load.
  ///
  /// Payload files include companions such as `.ucas` and `.utoc`, so presence
  /// of files alone does not make a folder a mod.
  static bool hasInstallablePayload(String dirPath) {
    return payloadFilesIn(dirPath).any((file) {
      final ext = p.extension(file).toLowerCase();
      return ext == '.pak' || ext == '.asi';
    });
  }

  /// Copies a mod folder into the library.
  ///
  /// Returns the imported mod, or null when the folder holds no installable
  /// files. Throws [StateError] when a mod of the same name already exists.
  NteMod? importDirectory(String sourcePath, {String? nameOverride}) {
    final source = Directory(sourcePath);
    if (!source.existsSync()) {
      throw ArgumentError('Source folder does not exist: $sourcePath');
    }

    if (!hasInstallablePayload(sourcePath)) return null;

    final name = nameOverride ?? p.basename(sourcePath);
    final target = Directory(p.join(rootPath, name));
    if (target.existsSync()) {
      throw StateError('A mod named "$name" is already in the library');
    }

    ensureExists();
    _copyDirectory(source, target);

    return _readMod(target.path);
  }

  /// Unpacks a zip archive into the library.
  ///
  /// Archives that contain one top-level folder are flattened so the mod is
  /// not nested twice. Returns null when nothing installable was found.
  NteMod? importArchive(String archivePath, {String? nameOverride}) {
    if (!isSupportedArchive(archivePath)) {
      throw ArgumentError('Unsupported archive format: ${p.extension(archivePath)}');
    }

    final name = nameOverride ?? p.basenameWithoutExtension(archivePath);
    final target = Directory(p.join(rootPath, name));
    if (target.existsSync()) {
      throw StateError('A mod named "$name" is already in the library');
    }

    final staging = Directory(
      p.join(Directory.systemTemp.path, 'nte_import_${DateTime.now().microsecondsSinceEpoch}'),
    )..createSync(recursive: true);

    try {
      extractFileToDisk(archivePath, staging.path);

      final contentRoot = _flattenedRoot(staging.path);
      if (!hasInstallablePayload(contentRoot)) return null;

      ensureExists();
      _copyDirectory(Directory(contentRoot), target);

      return _readMod(target.path);
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  /// Unwraps directories that contain nothing but a single subdirectory.
  static String _flattenedRoot(String dirPath) {
    var current = dirPath;

    while (true) {
      final entries = Directory(current).listSync();
      if (entries.length != 1 || entries.first is! Directory) return current;
      current = entries.first.path;
    }
  }

  /// Removes a mod from the library. Does not touch the game folder.
  void deleteMod(String name) {
    final dir = Directory(p.join(rootPath, name));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Renames a mod's folder, which is also its id.
  ///
  /// Callers must disable the mod first: the installed copy is keyed by the old
  /// name and would otherwise be orphaned in the game folder.
  NteMod renameMod(String oldName, String newName) {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Mod name cannot be empty');
    }
    if (trimmed.contains(RegExp(r'[/\\]'))) {
      throw ArgumentError('Mod name cannot contain path separators');
    }

    final source = Directory(p.join(rootPath, oldName));
    if (!source.existsSync()) {
      throw StateError('Mod "$oldName" is not in the library');
    }

    if (trimmed == oldName) return _readMod(source.path);

    final target = Directory(p.join(rootPath, trimmed));
    // A case-only rename maps to the same folder on case-insensitive systems,
    // so only a genuinely different mod counts as a conflict.
    if (target.existsSync() && trimmed.toLowerCase() != oldName.toLowerCase()) {
      throw StateError('A mod named "$trimmed" is already in the library');
    }

    source.renameSync(target.path);
    return _readMod(target.path);
  }

  /// Preview image stored inside a mod's folder, if it has one.
  String? previewImageFor(String name) {
    final dir = Directory(p.join(rootPath, name));
    if (!dir.existsSync()) return null;

    final images = dir
        .listSync()
        .whereType<File>()
        .where((f) => isPreviewImage(p.basename(f.path)))
        .map((f) => f.path)
        .toList();

    images.sort();
    return images.isEmpty ? null : images.first;
  }

  /// removes a mod's preview images, returns true if anything was deleted
  bool clearPreviewImage(String name) {
    final dir = Directory(p.join(rootPath, name));
    if (!dir.existsSync()) return false;

    var removed = false;
    for (final file in dir.listSync().whereType<File>()) {
      if (isPreviewImage(p.basename(file.path))) {
        file.deleteSync();
        removed = true;
      }
    }
    return removed;
  }

  /// Replaces a mod's preview image with [imageBytes].
  ///
  /// Existing previews are removed so the newest image is always the one shown.
  String setPreviewImage(String name, List<int> imageBytes, {String extension = 'png'}) {
    final dir = Directory(p.join(rootPath, name));
    if (!dir.existsSync()) {
      throw StateError('Mod "$name" is not in the library');
    }

    for (final file in dir.listSync().whereType<File>()) {
      if (isPreviewImage(p.basename(file.path))) file.deleteSync();
    }

    final target = p.join(dir.path, 'preview.$extension');
    File(target).writeAsBytesSync(imageBytes);
    return target;
  }

  static void _copyDirectory(Directory source, Directory target) {
    target.createSync(recursive: true);

    for (final entity in source.listSync(recursive: true)) {
      final relative = p.relative(entity.path, from: source.path);
      final destination = p.join(target.path, relative);

      if (entity is Directory) {
        Directory(destination).createSync(recursive: true);
      } else if (entity is File) {
        Directory(p.dirname(destination)).createSync(recursive: true);
        entity.copySync(destination);
      }
    }
  }
}
