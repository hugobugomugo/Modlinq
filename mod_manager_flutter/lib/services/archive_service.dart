import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as path;

import 'archive_formats.dart';

class ArchiveExtractionResult {
  final bool success;
  final String? error;
  final List<String>? extractedFolders;

  const ArchiveExtractionResult({
    required this.success,
    this.error,
    this.extractedFolders,
  });

  factory ArchiveExtractionResult.successResult(List<String> folders) =>
      ArchiveExtractionResult(
        success: true,
        extractedFolders: folders,
      );

  factory ArchiveExtractionResult.failure(String error) =>
      ArchiveExtractionResult(
        success: false,
        error: error,
      );
}

class ArchiveService {
  static bool isArchiveFile(String filePath) =>
      ArchiveFormats.isSupported(filePath);

  /// Whether a 7-Zip binary is present, which rar and 7z need.
  ///
  /// Lets callers hide those formats up front instead of letting the user pick
  /// a file that cannot be opened on this machine.
  static Future<bool> isExternalToolAvailable() async =>
      await _locate7Zip() != null;

  static Future<ArchiveExtractionResult> extractArchive({
    required File archiveFile,
    Directory? destinationDir,
  }) async {
    try {
      print('ArchiveService: extracting ${archiveFile.path}');

      final tempExtractDir = destinationDir ??
          await Directory.systemTemp.createTemp('zzz_archive_extract_');

      final error = await unpackInto(
        archiveFile: archiveFile,
        destination: tempExtractDir,
      );

      if (error != null) {
        print('ArchiveService: error: $error');
        return ArchiveExtractionResult.failure(error);
      }

      final directories = await _prepareDirectoriesForImport(
        tempExtractDir,
        archiveFile,
      );

      if (directories.isEmpty) {
        print('ArchiveService: archive is empty');
        return ArchiveExtractionResult.failure('archive contains no mod folders');
      }

      print('ArchiveService: found ${directories.length} folders');
      return ArchiveExtractionResult.successResult(directories);
    } catch (e) {
      print('ArchiveService: exception: $e');
      return ArchiveExtractionResult.failure('extraction failed: $e');
    }
  }

  /// Unpacks [archiveFile] into [destination], leaving the layout untouched.
  ///
  /// Returns null on success or the reason it failed. This is the one place
  /// that knows which format needs which unpacker, so the NTE library shares
  /// it instead of keeping a second, narrower list of its own.
  static Future<String?> unpackInto({
    required File archiveFile,
    required Directory destination,
  }) async {
    final extension = ArchiveFormats.extensionOf(archiveFile.path);

    if (extension == 'zip') {
      print('ArchiveService: zip archive');
      final extracted = await _extractZip(archiveFile, destination);
      return extracted ? null : 'could not extract archive';
    }

    if (ArchiveFormats.isNative(archiveFile.path)) {
      print('ArchiveService: tar archive ($extension)');
      return (await _extractTar(archiveFile, destination)).error;
    }

    if (ArchiveFormats.needsExternalTool(archiveFile.path)) {
      print('ArchiveService: rar/7z archive');
      return (await _extractWith7Zip(archiveFile, destination)).error;
    }

    return 'archive format not supported';
  }

  /// Unpacks a zip on a background isolate.
  ///
  /// `ZipDecoder.decodeBytes` is synchronous CPU work over the whole archive.
  /// Running it on the UI isolate froze the window for as long as it took —
  /// seconds for the 200 MB packs the marketplace hands over.
  static Future<bool> _extractZip(File archiveFile, Directory destination) async {
    final archivePath = archiveFile.path;
    final destinationPath = destination.path;

    try {
      final extracted = await Isolate.run(
        () => extractZipSync(archivePath, destinationPath),
      );

      print('ArchiveService: zip extracted, files: $extracted');
      return true;
    } catch (e) {
      print('ArchiveService: zip extraction failed: $e');
      return false;
    }
  }

  /// The actual unpacking, free of anything isolate-unfriendly.
  ///
  /// Returns how many files were written. Entries whose path would escape the
  /// destination are skipped rather than trusted.
  static int extractZipSync(String archivePath, String destinationPath) {
    final bytes = File(archivePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);

    var extracted = 0;
    for (final file in archive) {
      final sanitizedPath = _sanitizeArchivePath(destinationPath, file.name);
      if (sanitizedPath == null) continue;

      if (file.isFile) {
        File(sanitizedPath)
          ..createSync(recursive: true)
          ..writeAsBytesSync(file.content as List<int>);
        extracted++;
      } else {
        Directory(sanitizedPath).createSync(recursive: true);
      }
    }

    return extracted;
  }

  /// Unpacks tar and the compressed tarballs, none of which need a tool.
  ///
  /// `extractFileToDisk` decides the codec from the file name, so the name has
  /// to survive: a mod called `Skin.tar.gz` must not reach here as `Skin.gz`.
  static Future<_ExtractionOutcome> _extractTar(
    File archiveFile,
    Directory destination,
  ) async {
    final archivePath = archiveFile.path;
    final destinationPath = destination.path;

    try {
      // Same reason as the zip path: the codecs are synchronous, so they run
      // where a stalled thread costs nothing.
      await Isolate.run(
        () => extractFileToDisk(archivePath, destinationPath),
      );
      print('ArchiveService: tar extraction ok');
      return const _ExtractionOutcome(true);
    } catch (e) {
      print('ArchiveService: tar extraction failed: $e');
      return _ExtractionOutcome(false, 'could not extract archive: $e');
    }
  }

  static Future<_ExtractionOutcome> _extractWith7Zip(
    File archiveFile,
    Directory destination,
  ) async {
    final sevenZipPath = await _locate7Zip();
    if (sevenZipPath == null) {
      return _ExtractionOutcome(
        false,
        '7-zip not found. install 7-zip to extract rar/7z.',
      );
    }

    print('ArchiveService: using 7-zip: $sevenZipPath');

    final result = await Process.run(sevenZipPath, [
      'x',
      archiveFile.path,
      '-o${destination.path}',
      '-y',
    ]);

    if (result.exitCode != 0) {
      final errorOutput = result.stderr.toString().trim();
      print('ArchiveService: 7-zip error: $errorOutput');
      return _ExtractionOutcome(
        false,
        errorOutput.isNotEmpty ? errorOutput : 'could not extract archive',
      );
    }

    print('ArchiveService: 7-zip extraction ok');
    return const _ExtractionOutcome(true);
  }

  static Future<String?> _locate7Zip() async {
    if (Platform.isWindows) {
      final whereResult = await Process.run('where', ['7z']);
      if (whereResult.exitCode == 0) {
        final lines = whereResult.stdout
            .toString()
            .split(RegExp(r'[\r\n]+'))
            .where((line) => line.trim().isNotEmpty);
        if (lines.isNotEmpty) {
          return lines.first.trim();
        }
      }

      final candidates = [
        path.join(
          Platform.environment['ProgramFiles'] ?? '',
          '7-Zip',
          '7z.exe',
        ),
        path.join(
          Platform.environment['ProgramFiles(x86)'] ?? '',
          '7-Zip',
          '7z.exe',
        ),
      ];

      for (final candidate in candidates) {
        if (candidate.trim().isEmpty) continue;
        final file = File(candidate);
        if (await file.exists()) {
          return file.path;
        }
      }
      return null;
    }

    if (Platform.isLinux || Platform.isMacOS) {
      final commands = ['7z', '7za', '7zr'];
      for (final command in commands) {
        try {
          final whichResult = await Process.run('which', [command]);
          if (whichResult.exitCode == 0) {
            final pathResult = whichResult.stdout
                .toString()
                .split(RegExp(r'[\r\n]+'))
                .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '')
                .trim();
            if (pathResult.isNotEmpty) {
              return pathResult;
            }
          }
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  static Future<List<String>> _prepareDirectoriesForImport(
    Directory extractDir,
    File archiveFile,
  ) async {
    final entries = extractDir.listSync();
    final directories = <String>[];

    if (entries.isEmpty) {
      return directories;
    }

    final dirEntries = entries.whereType<Directory>().toList();
    if (dirEntries.isEmpty) {
      final baseName = ArchiveFormats.baseNameOf(archiveFile.path);
      final wrapperDir = Directory(path.join(extractDir.path, baseName));
      await wrapperDir.create(recursive: true);

      for (final entity in entries) {
        final targetPath = path.join(
          wrapperDir.path,
          path.basename(entity.path),
        );
        if (entity is File) {
          await entity.copy(targetPath);
          await entity.delete();
        } else if (entity is Directory) {
          await Directory(entity.path).rename(targetPath);
        }
      }
      directories.add(wrapperDir.path);
      return directories;
    }

    for (final dir in dirEntries) {
      directories.add(dir.path);
    }

    return directories;
  }

  static String? _sanitizeArchivePath(String base, String relativePath) {
    final normalized = path.normalize(relativePath);
    if (normalized.contains('..')) {
      return null;
    }
    final fullPath = path.join(base, normalized);
    if (!path.isWithin(base, fullPath)) {
      return null;
    }
    return fullPath;
  }
}

class _ExtractionOutcome {
  final bool success;
  final String? error;

  const _ExtractionOutcome(this.success, [this.error]);
}
