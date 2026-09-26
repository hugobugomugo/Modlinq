// The manifest is what a repair trusts, so a stale one is worse than none:
// it would report a healthy install as corrupt, or wave a swapped binary
// through. This test recomputes it and fails when the two disagree.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/gen_integrity.dart' as gen;

void main() {
  test('the committed manifest matches the files on disk', () {
    final onDisk = gen.encodeManifest(gen.buildEntries());
    final committed = File(gen.manifestPath).readAsStringSync();

    expect(
      committed,
      onDisk,
      reason: 'assets/ changed without regenerating the manifest. '
          'Run: dart run tool/gen_integrity.dart',
    );
  });

  test('every guarded folder is covered', () {
    final entries = (jsonDecode(File(gen.manifestPath).readAsStringSync())
        as Map<String, dynamic>)['files'] as List;
    final assets = entries.map((e) => (e as Map)['asset'] as String).toSet();

    for (final dir in gen.guardedDirs) {
      expect(
        assets.any((asset) => asset.startsWith('$dir/')),
        isTrue,
        reason: '$dir has no manifest entry',
      );
    }

    // The file antivirus actually removes must never fall out of the set.
    expect(assets, contains('assets/nte_loader/loader.asi'));
  });
}
