import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../utils/path_helper.dart';

/// Gives code that copies files a real on-disk path for a bundled asset.
///
/// Assets live inside the app bundle, so anything that has to hand a path to
/// another process — or simply copy bytes around — needs them extracted first.
abstract class BundledFileSource {
  /// Absolute path of [assetKey]'s on-disk copy.
  Future<String> resolve(String assetKey);

  /// Root all resolved paths share, so it can be passed to a helper process.
  String get rootPath;
}

/// Extracts bundled assets into the app data folder and reuses them.
class BundledAssetCache implements BundledFileSource {
  BundledAssetCache({String? rootPath})
    : rootPath = rootPath ?? p.join(PathHelper.getAppDataPath(), 'bundled');

  @override
  final String rootPath;

  @override
  Future<String> resolve(String assetKey) async {
    final target = File(p.join(rootPath, p.joinAll(p.posix.split(assetKey))));
    final data = await rootBundle.load(assetKey);

    // Size is enough to spot a stale copy: an app update ships a different
    // loader build, and a truncated extraction never matches either.
    if (target.existsSync() && target.lengthSync() == data.lengthInBytes) {
      return target.path;
    }

    target.parent.createSync(recursive: true);
    await target.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );

    return target.path;
  }
}

/// Reads the same layout straight from a folder.
///
/// Used by the elevated helper, which is handed an already extracted asset
/// root, and by tests that never touch the Flutter asset bundle.
class DirectoryFileSource implements BundledFileSource {
  DirectoryFileSource(this.rootPath);

  @override
  final String rootPath;

  @override
  Future<String> resolve(String assetKey) async =>
      p.join(rootPath, p.joinAll(p.posix.split(assetKey)));
}
