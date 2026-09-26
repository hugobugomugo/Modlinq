import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

/// Verifies that the files this app ships are still on disk and unmodified.
///
/// Antivirus treats the NTE mod loader as what it structurally is — a DLL
/// injector — and quarantines `loader.asi` out of the installed app. Nothing
/// in the app notices until a loader install fails with a Flutter asset error
/// that means nothing to a user. This turns that into a named, repairable
/// state.

/// How a guarded file compares to the manifest.
enum IntegrityState {
  ok,

  /// Gone from disk. Antivirus removal looks like this.
  missing,

  /// Present but not the file that shipped.
  corrupt,
}

/// The manifest could not be read or parsed.
///
/// Never downgraded to "healthy": a repair that trusts a broken manifest
/// would either overwrite a good install or wave a swapped binary through.
class IntegrityManifestException implements Exception {
  final String message;
  const IntegrityManifestException(this.message);

  @override
  String toString() => 'IntegrityManifestException: $message';
}

/// One guarded file as `assets/integrity.json` describes it.
class IntegrityEntry {
  final String assetKey;
  final int bytes;
  final String sha256;

  const IntegrityEntry({
    required this.assetKey,
    required this.bytes,
    required this.sha256,
  });

  static IntegrityEntry fromJson(Map<String, dynamic> json) => IntegrityEntry(
    assetKey: json['asset'] as String,
    bytes: json['bytes'] as int,
    sha256: json['sha256'] as String,
  );
}

/// The verdict on a single guarded file.
class IntegrityFile {
  final IntegrityEntry expected;

  /// Where the file lives in the installed app.
  final String path;
  final IntegrityState state;

  /// Size found on disk, null when the file is gone.
  final int? actualBytes;

  const IntegrityFile({
    required this.expected,
    required this.path,
    required this.state,
    this.actualBytes,
  });

  String get assetKey => expected.assetKey;
}

class IntegrityReport {
  final List<IntegrityFile> files;

  const IntegrityReport(this.files);

  List<IntegrityFile> get broken =>
      files.where((file) => file.state != IntegrityState.ok).toList();

  bool get healthy => broken.isEmpty;

  /// Total bytes a repair has to put back.
  int get brokenBytes =>
      broken.fold(0, (sum, file) => sum + file.expected.bytes);
}

class IntegrityService {
  /// Root of the installed app: the folder holding the executable.
  final Directory installDir;

  /// Reads `assets/integrity.json`. Injected in tests.
  final Future<String> Function() readManifest;

  IntegrityService({
    required this.installDir,
    Future<String> Function()? readManifest,
  }) : readManifest = readManifest ?? _readBundledManifest;

  static const String manifestAsset = 'assets/integrity.json';

  static Future<String> _readBundledManifest() {
    // The manifest is JSON, so antivirus leaves it alone even when it takes
    // the binaries it describes. Evicting first keeps a cached copy from
    // masking a file that was removed mid-session.
    rootBundle.evict(manifestAsset);
    return rootBundle.loadString(manifestAsset);
  }

  /// Absolute path of [assetKey] inside the installed app.
  String pathOf(String assetKey) => p.join(
    installDir.path,
    'data',
    'flutter_assets',
    p.joinAll(p.posix.split(assetKey)),
  );

  Future<List<IntegrityEntry>> _manifest() async {
    final Object? decoded;
    try {
      decoded = jsonDecode(await readManifest());
    } catch (e) {
      throw IntegrityManifestException('$manifestAsset is not valid JSON: $e');
    }

    if (decoded is! Map<String, dynamic> || decoded['files'] is! List) {
      throw IntegrityManifestException('$manifestAsset has no "files" list');
    }

    try {
      return (decoded['files'] as List)
          .cast<Map<String, dynamic>>()
          .map(IntegrityEntry.fromJson)
          .toList();
    } catch (e) {
      throw IntegrityManifestException('$manifestAsset has a bad entry: $e');
    }
  }

  Future<IntegrityReport> check() async {
    final entries = await _manifest();
    final files = <IntegrityFile>[];

    for (final entry in entries) {
      files.add(await _checkOne(entry));
    }

    return IntegrityReport(files);
  }

  Future<IntegrityFile> _checkOne(IntegrityEntry entry) async {
    final path = pathOf(entry.assetKey);
    final file = File(path);

    if (!file.existsSync()) {
      return IntegrityFile(
        expected: entry,
        path: path,
        state: IntegrityState.missing,
      );
    }

    // Size first: it is free, and a wrong size cannot become the right hash,
    // so the 33 MB loader is only ever read when it might still be good.
    final size = file.lengthSync();
    if (size != entry.bytes) {
      return IntegrityFile(
        expected: entry,
        path: path,
        state: IntegrityState.corrupt,
        actualBytes: size,
      );
    }

    // Streamed rather than read whole: the loader alone is 33 MB, and this
    // runs on the UI isolate.
    final digest = await sha256.bind(file.openRead()).first;
    final matches =
        digest.toString().toLowerCase() == entry.sha256.toLowerCase();

    return IntegrityFile(
      expected: entry,
      path: path,
      state: matches ? IntegrityState.ok : IntegrityState.corrupt,
      actualBytes: size,
    );
  }
}
