import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../core/app_version.dart';
import 'app_log.dart';
import 'elevated_file_copy.dart';
import 'integrity_service.dart';
import 'update_service.dart';

/// A repair could not be completed safely.
///
/// Always thrown rather than swallowed: a half-repaired install that still
/// reports success is how the user ends up chasing the same bug twice.
class IntegrityRepairException implements Exception {
  final String message;
  const IntegrityRepairException(this.message);

  @override
  String toString() => 'IntegrityRepairException: $message';
}

class RepairResult {
  /// Asset keys written back, in manifest order.
  final List<String> restored;

  const RepairResult(this.restored);
}

/// Puts files back that antivirus removed from the installed app.
///
/// The bytes are gone, so they have to come from outside: the release this
/// build was made from. Everything extracted is checked against the local
/// manifest before it is allowed near the install folder, which means a
/// tampered or mismatched download can never be what gets installed.
class IntegrityRepair {
  final IntegrityService integrity;

  /// Produces the release package for this exact build, already verified
  /// against its published checksum.
  final Future<File> Function() fetchPackage;

  /// Copies `source -> destination`, elevating when the install folder needs
  /// it. Separate because only this step requires administrator rights.
  final Future<void> Function(Map<String, String> fromTo) placeFiles;

  const IntegrityRepair({
    required this.integrity,
    required this.fetchPackage,
    required this.placeFiles,
  });

  /// Wires the repair against the real install: the release this build came
  /// from, downloaded and checksum-verified, written back through UAC when
  /// the app lives somewhere the user cannot write.
  static IntegrityRepair forInstalledApp({
    UpdateService? updates,
    String version = appVersion,
  }) {
    final service = updates ?? UpdateService();

    return IntegrityRepair(
      integrity: IntegrityService(installDir: UpdateService.installDir()),
      fetchPackage: () async {
        final info = await service.findReleaseFor(version);
        if (info == null) {
          throw IntegrityRepairException(
            'no published release matches version $version, '
            'so there is nothing to restore from',
          );
        }

        final file = await service.downloadAsset(info);
        final expected = await service.fetchExpectedChecksum(info);
        if (expected != null && !await service.verifyChecksum(file, expected)) {
          throw const IntegrityRepairException(
            'the downloaded release package failed its published checksum',
          );
        }

        return file;
      },
      placeFiles: ElevatedFileCopy.place,
    );
  }

  /// Where a guarded asset sits inside the release archive.
  static String archivePathOf(String assetKey) =>
      'data/flutter_assets/$assetKey';

  Future<RepairResult> run(IntegrityReport report) async {
    if (report.healthy) return const RepairResult([]);

    final broken = report.broken;
    AppLog.warn(
      'Repairing ${broken.length} damaged app file(s)',
      details: broken
          .map((f) => '${f.assetKey}: ${f.state.name}')
          .join('\n'),
    );

    final package = await fetchPackage();
    final staging = await Directory.systemTemp.createTemp('modlinq-repair');

    try {
      final wanted = {
        for (final file in broken) archivePathOf(file.assetKey): p.join(
          staging.path,
          p.joinAll(p.posix.split(file.assetKey)),
        ),
      };

      final packagePath = package.path;
      final extracted = await Isolate.run(
        () => _extractSelected(packagePath, wanted),
      );

      final fromTo = <String, String>{};
      for (final file in broken) {
        final staged = wanted[archivePathOf(file.assetKey)]!;
        if (!extracted.contains(archivePathOf(file.assetKey))) {
          throw IntegrityRepairException(
            'the release package does not contain ${file.assetKey}',
          );
        }

        await _verifyStaged(staged, file);
        fromTo[staged] = file.path;
      }

      await placeFiles(fromTo);

      AppLog.info(
        'Restored ${fromTo.length} app file(s)',
        details: broken.map((f) => f.path).join('\n'),
      );

      return RepairResult(broken.map((f) => f.assetKey).toList());
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    }
  }

  /// Refuses anything that is not byte-for-byte what this build shipped.
  Future<void> _verifyStaged(String staged, IntegrityFile file) async {
    final onDisk = File(staged);
    final size = onDisk.lengthSync();

    if (size != file.expected.bytes) {
      throw IntegrityRepairException(
        '${file.assetKey} in the release package is $size bytes, '
        'expected ${file.expected.bytes}',
      );
    }

    final digest = await sha256.bind(onDisk.openRead()).first;
    if (digest.toString().toLowerCase() !=
        file.expected.sha256.toLowerCase()) {
      throw IntegrityRepairException(
        '${file.assetKey} in the release package does not match this build',
      );
    }
  }

  /// Pulls only [wanted] out of the zip, keyed archive path -> target path.
  ///
  /// Runs in an isolate: the release archive is around 50 MB and decoding it
  /// on the UI isolate freezes the window for the whole duration.
  static Set<String> _extractSelected(
    String archivePath,
    Map<String, String> wanted,
  ) {
    final archive = ZipDecoder().decodeBytes(
      File(archivePath).readAsBytesSync(),
      verify: true,
    );

    final found = <String>{};
    for (final entry in archive) {
      if (!entry.isFile) continue;

      // Zip entries can use either separator depending on the packer.
      final name = entry.name.replaceAll('\\', '/');
      final target = wanted[name];
      if (target == null) continue;

      File(target)
        ..createSync(recursive: true)
        ..writeAsBytesSync(entry.content as List<int>);
      found.add(name);
    }

    return found;
  }
}
