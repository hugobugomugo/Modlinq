import 'dart:io';

import 'package:path/path.dart' as p;

import 'bundled_files.dart';
import 'nte_game_detection.dart';

/// What of the loader is currently present in the game folder.
class NteLoaderStatus {
  final bool valid;
  final String loaderDir;
  final bool asiFound;
  final bool cutilsFound;
  final bool proxyFound;
  final List<String> proxyNames;
  final List<String> missingFiles;

  const NteLoaderStatus({
    required this.valid,
    required this.loaderDir,
    required this.asiFound,
    required this.cutilsFound,
    required this.proxyFound,
    required this.proxyNames,
    required this.missingFiles,
  });

  Map<String, dynamic> toJson() => {
    'valid': valid,
    'loaderDir': loaderDir,
    'asiFound': asiFound,
    'cutilsFound': cutilsFound,
    'proxyFound': proxyFound,
    'proxyNames': proxyNames,
    'missingFiles': missingFiles,
  };

  static NteLoaderStatus fromJson(Map<String, dynamic> json) => NteLoaderStatus(
    valid: json['valid'] as bool? ?? false,
    loaderDir: json['loaderDir'] as String? ?? '',
    asiFound: json['asiFound'] as bool? ?? false,
    cutilsFound: json['cutilsFound'] as bool? ?? false,
    proxyFound: json['proxyFound'] as bool? ?? false,
    proxyNames: (json['proxyNames'] as List?)?.cast<String>() ?? const [],
    missingFiles: (json['missingFiles'] as List?)?.cast<String>() ?? const [],
  );
}

/// Installs the NTE mod loader into a game folder.
///
/// Ported from NTEMM's `src-tauri/src/game/loader.rs`. Three bundled files end
/// up in `Binaries/Win64`: `loader.asi`, `subloader.dll` renamed to
/// `cutils.dll`, and `loader.dll` copied once per proxy DLL name the edition
/// hooks. Which proxy name works is a property of the game build, not a user
/// preference, so the names are fixed per edition.
class NteLoaderInstaller {
  final String gameRoot;
  final NteEdition edition;
  final BundledFileSource source;

  NteLoaderInstaller({
    required this.gameRoot,
    required this.edition,
    required this.source,
  });

  static const String loaderAsiAsset = 'assets/nte_loader/loader.asi';
  static const String subloaderAsset = 'assets/nte_loader/subloader.dll';
  static const String proxyDllAsset = 'assets/nte_loader/loader.dll';

  static const String loaderAsiName = 'loader.asi';
  static const String cutilsName = 'cutils.dll';

  /// Every proxy name any edition has ever used. Uninstall clears all of them
  /// so switching editions cannot leave a stale hook behind.
  static const List<String> knownProxyNames = [
    'version.dll',
    'dsound.dll',
    'dinput8.dll',
  ];

  /// `.asi` plugins the loader owns, removed together with it.
  static const List<String> managedAsiNames = [
    loaderAsiName,
    'Anticensor.asi',
    'AyakaNTEModLoader.asi',
  ];

  static List<String> proxyNamesFor(NteEdition edition) => switch (edition) {
    NteEdition.cn => const ['dsound.dll', 'dinput8.dll'],
    _ => const ['version.dll'],
  };

  List<String> get proxyNames => proxyNamesFor(edition);

  String get loaderDir =>
      p.join(gameRoot, 'Client', 'WindowsNoEditor', 'HT', 'Binaries', 'Win64');

  String get paksModsDir => p.join(
    gameRoot,
    'Client',
    'WindowsNoEditor',
    'HT',
    'Content',
    'Paks',
    '~mods',
  );

  /// Which loader files are installed right now.
  NteLoaderStatus status() {
    final asiFound = File(p.join(loaderDir, loaderAsiName)).existsSync();
    final cutilsFound = File(p.join(loaderDir, cutilsName)).existsSync();

    final missing = <String>[
      if (!asiFound) loaderAsiName,
      if (!cutilsFound) cutilsName,
      ...proxyNames.where((name) => !File(p.join(loaderDir, name)).existsSync()),
    ];

    return NteLoaderStatus(
      valid: missing.isEmpty,
      loaderDir: loaderDir,
      asiFound: asiFound,
      cutilsFound: cutilsFound,
      proxyFound: proxyNames.every(
        (name) => File(p.join(loaderDir, name)).existsSync(),
      ),
      proxyNames: proxyNames,
      missingFiles: missing,
    );
  }

  /// Copies the bundled loader in, replacing whatever is there.
  ///
  /// Proxy names this edition does not use are removed first, so a folder set
  /// up for another edition cannot end up with two live hooks.
  Future<NteLoaderStatus> install() async {
    Directory(loaderDir).createSync(recursive: true);

    final loaderAsi = await source.resolve(loaderAsiAsset);
    final subloader = await source.resolve(subloaderAsset);
    final proxyDll = await source.resolve(proxyDllAsset);

    for (final asset in [loaderAsi, subloader, proxyDll]) {
      if (!File(asset).existsSync()) {
        throw StateError('Bundled loader file not found: $asset');
      }
    }

    copyIfChanged(loaderAsi, p.join(loaderDir, loaderAsiName));
    copyIfChanged(subloader, p.join(loaderDir, cutilsName));

    for (final name in knownProxyNames) {
      if (proxyNames.any((used) => _sameName(used, name))) continue;
      _removeFile(p.join(loaderDir, name));
    }

    for (final name in proxyNames) {
      copyIfChanged(proxyDll, p.join(loaderDir, name));
    }

    return status();
  }

  /// Removes the loader, its managed `.asi` plugins and every known proxy DLL.
  NteLoaderStatus uninstall() {
    for (final name in managedAsiNames) {
      _removeFileAndLog(p.join(loaderDir, name));
    }
    _removeFile(p.join(loaderDir, cutilsName));

    for (final name in knownProxyNames) {
      _removeFile(p.join(loaderDir, name));
    }

    return status();
  }

  /// Uninstalls the loader and wipes every installed mod from the game folder.
  ///
  /// [installedAsiNames] are the file names of `.asi` mods this app installed,
  /// which live next to the loader and are not covered by wiping `~mods`.
  NteLoaderStatus cleanGameMods({Iterable<String> installedAsiNames = const []}) {
    final paks = Directory(paksModsDir);
    if (paks.existsSync()) paks.deleteSync(recursive: true);

    for (final name in installedAsiNames) {
      _removeFileAndLog(p.join(loaderDir, name));
    }

    return uninstall();
  }

  static bool _sameName(String a, String b) =>
      a.toLowerCase() == b.toLowerCase();

  /// Copies [source] over [target] unless the bytes already match.
  ///
  /// Skipping an identical copy matters on Windows: the game holds the loader
  /// open while it runs, so rewriting a file that needs no change would fail
  /// for no reason. Timestamps are useless here because a copy gets a fresh
  /// one, so the contents are compared instead.
  static void copyIfChanged(String source, String target) {
    final from = File(source);
    final to = File(target);

    if (to.existsSync() && _sameContents(from, to)) return;

    Directory(p.dirname(target)).createSync(recursive: true);
    from.copySync(target);
  }

  static bool _sameContents(File a, File b) {
    if (a.lengthSync() != b.lengthSync()) return false;

    // Chunked: the loader is 30 MB+, reading both into memory to compare them
    // is not worth it.
    const chunkSize = 1 << 20;
    final readerA = a.openSync();
    final readerB = b.openSync();

    try {
      while (true) {
        final chunkA = readerA.readSync(chunkSize);
        final chunkB = readerB.readSync(chunkSize);

        if (chunkA.length != chunkB.length) return false;
        if (chunkA.isEmpty) return true;

        for (var i = 0; i < chunkA.length; i++) {
          if (chunkA[i] != chunkB[i]) return false;
        }
      }
    } finally {
      readerA.closeSync();
      readerB.closeSync();
    }
  }

  void _removeFile(String path) {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  }

  /// `.asi` plugins write a log next to themselves; leaving it behind makes a
  /// removed plugin look installed to the user.
  void _removeFileAndLog(String path) {
    _removeFile(path);

    if (p.extension(path).toLowerCase() != '.asi') return;
    _removeFile(p.setExtension(path, '.log'));
  }
}
