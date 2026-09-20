import 'dart:io';

import 'package:path/path.dart' as p;

import 'bundled_files.dart';
import 'nte_loader_installer.dart';

/// Extras shipped with the app rather than imported by the user.
enum NteBundledMod {
  /// `.asi` plugin, needs the loader to run.
  anticensor,

  /// Pak mod that hides the UID overlay, loaded by the game itself.
  hideUid,
}

class _BundledModSpec {
  final String assetDir;
  final List<String> files;

  /// Folder under `~mods/UI` for pak mods, null for `.asi` plugins that go
  /// next to the game binary.
  final String? uiFolder;

  const _BundledModSpec({
    required this.assetDir,
    required this.files,
    this.uiFolder,
  });

  bool get isAsi => uiFolder == null;
}

/// Result of inspecting or toggling a bundled mod.
class NteBundledModStatus {
  final bool installed;
  final bool loaderInstalled;
  final String message;

  const NteBundledModStatus({
    required this.installed,
    required this.loaderInstalled,
    required this.message,
  });
}

/// Installs the extras that ship with the app: Anticensor and Hide UID.
///
/// Ported from NTEMM's `mods/anticensor.rs` and `mods/ui_mods.rs`. Hide Ping
/// exists upstream but its paks were never bundled, so it is left out until
/// the files are available rather than shipped as a dead toggle.
class NteBundledModsInstaller {
  final String gameRoot;
  final BundledFileSource source;
  final NteLoaderInstaller loader;

  NteBundledModsInstaller({
    required this.gameRoot,
    required this.source,
    required this.loader,
  });

  static const Map<NteBundledMod, _BundledModSpec> _specs = {
    NteBundledMod.anticensor: _BundledModSpec(
      assetDir: 'assets/nte_bundled/Anticensor',
      files: ['Anticensor.asi'],
    ),
    NteBundledMod.hideUid: _BundledModSpec(
      assetDir: 'assets/nte_bundled/Hide_UID',
      files: ['Hide_UID_P.pak', 'Hide_UID_P.ucas', 'Hide_UID_P.utoc'],
      uiFolder: 'Hide_UID',
    ),
  };

  String get _uiModsRoot => p.join(loader.paksModsDir, 'UI');

  String targetDirOf(NteBundledMod mod) {
    final spec = _specs[mod]!;
    return spec.isAsi ? loader.loaderDir : p.join(_uiModsRoot, spec.uiFolder!);
  }

  List<String> targetFilesOf(NteBundledMod mod) {
    final dir = targetDirOf(mod);
    return _specs[mod]!.files.map((name) => p.join(dir, name)).toList();
  }

  bool isInstalled(NteBundledMod mod) =>
      targetFilesOf(mod).every((path) => File(path).existsSync());

  NteBundledModStatus statusOf(NteBundledMod mod) {
    final loaderValid = loader.status().valid;
    final installed = isInstalled(mod);

    return NteBundledModStatus(
      installed: installed,
      loaderInstalled: loaderValid,
      message: _messageFor(mod, installed, loaderValid),
    );
  }

  /// Turns [mod] on or off.
  ///
  /// An `.asi` plugin without the loader would sit in the folder doing
  /// nothing, so enabling one is refused and any stale copy is removed - the
  /// user sees an off toggle that matches reality instead of a silent no-op.
  Future<NteBundledModStatus> setEnabled(NteBundledMod mod, bool enabled) async {
    final spec = _specs[mod]!;
    final loaderValid = loader.status().valid;

    if (enabled && spec.isAsi && !loaderValid) {
      _removeInstalled(mod);

      return NteBundledModStatus(
        installed: false,
        loaderInstalled: false,
        message: 'Install the loader first',
      );
    }

    if (!enabled) {
      _removeInstalled(mod);
      return statusOf(mod);
    }

    final targetDir = targetDirOf(mod);
    Directory(targetDir).createSync(recursive: true);

    for (final name in spec.files) {
      final asset = await source.resolve('${spec.assetDir}/$name');
      if (!File(asset).existsSync()) {
        throw StateError('Bundled mod file not found: $asset');
      }

      NteLoaderInstaller.copyIfChanged(asset, p.join(targetDir, name));
    }

    return statusOf(mod);
  }

  /// Removes both bundled mods, used when clearing the game folder.
  void removeAll() {
    for (final mod in NteBundledMod.values) {
      _removeInstalled(mod);
    }
  }

  void _removeInstalled(NteBundledMod mod) {
    final spec = _specs[mod]!;

    for (final path in targetFilesOf(mod)) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();

      if (!spec.isAsi) continue;
      final log = File(p.setExtension(path, '.log'));
      if (log.existsSync()) log.deleteSync();
    }

    if (spec.isAsi) return;

    // Pak mods own their folder, so an empty leftover would still show up in
    // the game's mod list as an empty entry.
    final dir = Directory(targetDirOf(mod));
    if (dir.existsSync() && dir.listSync().isEmpty) dir.deleteSync();
  }

  String _messageFor(NteBundledMod mod, bool installed, bool loaderValid) {
    if (!installed) return '${_label(mod)} is not installed';
    if (_specs[mod]!.isAsi && !loaderValid) {
      return '${_label(mod)} is installed, but loader files are missing';
    }
    return '${_label(mod)} is installed';
  }

  static String _label(NteBundledMod mod) => switch (mod) {
    NteBundledMod.anticensor => 'Anticensor',
    NteBundledMod.hideUid => 'Hide UID',
  };
}
