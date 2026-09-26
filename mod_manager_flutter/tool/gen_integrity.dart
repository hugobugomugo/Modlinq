// Regenerates assets/integrity.json.
//
// Run after replacing any bundled loader binary:
//   fvm dart run tool/gen_integrity.dart
//
// integrity_manifest_test.dart fails when the committed manifest and the
// files on disk disagree, so this can never silently rot.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Folders whose contents antivirus is known to remove: the loader is an ASI
/// injector and the bundled extras ship next to it.
const List<String> guardedDirs = ['assets/nte_loader', 'assets/nte_bundled'];

const String manifestPath = 'assets/integrity.json';

/// Every guarded file as `{asset, bytes, sha256}`, sorted by asset key so the
/// output is stable across machines.
List<Map<String, Object>> buildEntries({String root = '.'}) {
  final entries = <Map<String, Object>>[];

  for (final dir in guardedDirs) {
    final directory = Directory(p.join(root, dir));
    if (!directory.existsSync()) continue;

    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      final bytes = file.readAsBytesSync();
      entries.add({
        'asset': p.posix.joinAll(p.split(p.relative(file.path, from: root))),
        'bytes': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
      });
    }
  }

  entries.sort((a, b) => (a['asset'] as String).compareTo(b['asset'] as String));
  return entries;
}

String encodeManifest(List<Map<String, Object>> entries) =>
    '${const JsonEncoder.withIndent('  ').convert({'files': entries})}\n';

void main() {
  final entries = buildEntries();
  File(manifestPath).writeAsStringSync(encodeManifest(entries));
  stdout.writeln('wrote ${entries.length} entries to $manifestPath');
}
