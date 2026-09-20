import 'bundled_files.dart';
import 'config_service.dart';
import 'nte_bundled_mods.dart';
import 'nte_game_detection.dart';
import 'nte_loader_installer.dart';
import 'nte_loader_task.dart';

/// Single entry point for everything the app installs into an NTE folder that
/// is not a user mod: the loader itself, Anticensor and Hide UID.
///
/// Callers never touch [NteLoaderInstaller] directly, because every write has
/// to be able to fall back to the elevated helper on Windows.
class NteLoaderService {
  final String gameRoot;
  final NteEdition edition;
  final BundledFileSource source;

  late final NteLoaderInstaller installer = NteLoaderInstaller(
    gameRoot: gameRoot,
    edition: edition,
    source: source,
  );

  late final NteBundledModsInstaller bundledMods = NteBundledModsInstaller(
    gameRoot: gameRoot,
    source: source,
    loader: installer,
  );

  NteLoaderService({
    required this.gameRoot,
    required this.edition,
    required this.source,
  });

  /// Builds a service for the configured game folder, or null when none is set
  /// or the folder is not a valid install.
  static NteLoaderService? fromConfig(
    ConfigService config, {
    BundledFileSource? source,
  }) {
    final gamePath = config.nteGamePath;
    if (gamePath == null || gamePath.isEmpty) return null;

    final install = NteGameDetection.validate(gamePath);
    if (!install.valid) return null;

    return NteLoaderService(
      gameRoot: gamePath,
      edition: install.edition,
      source: source ?? BundledAssetCache(),
    );
  }

  NteLoaderStatus get status => installer.status();

  /// Installs the loader unless it is already complete.
  ///
  /// Called before a mod is installed, so mods never land in a folder the game
  /// cannot load them from.
  Future<NteLoaderStatus> ensureInstalled() async {
    final current = status;
    if (current.valid) return current;

    return install();
  }

  Future<NteLoaderStatus> install() => _run(NteLoaderTaskKind.install);

  Future<NteLoaderStatus> uninstall() => _run(NteLoaderTaskKind.uninstall);

  /// Wipes every installed mod plus the loader. [installedAsiNames] are the
  /// `.asi` files of library mods, which live outside `~mods`.
  Future<NteLoaderStatus> clean({
    Iterable<String> installedAsiNames = const [],
  }) => _run(
    NteLoaderTaskKind.clean,
    installedAsiNames: installedAsiNames.toList(),
  );

  bool isBundledModInstalled(NteBundledMod mod) =>
      bundledMods.isInstalled(mod);

  NteBundledModStatus bundledModStatus(NteBundledMod mod) =>
      bundledMods.statusOf(mod);

  /// Toggles a bundled extra. Anticensor needs the loader, so it is installed
  /// first rather than failing in a way the user has to understand.
  Future<NteBundledModStatus> setBundledMod(
    NteBundledMod mod,
    bool enabled,
  ) async {
    if (enabled && mod == NteBundledMod.anticensor) {
      final loaderStatus = await ensureInstalled();
      if (!loaderStatus.valid) {
        return NteBundledModStatus(
          installed: false,
          loaderInstalled: false,
          message: 'Loader files are missing',
        );
      }
    }

    await _run(
      NteLoaderTaskKind.bundledMod,
      bundledMod: mod,
      bundledEnabled: enabled,
    );

    return bundledMods.statusOf(mod);
  }

  Future<NteLoaderStatus> _run(
    NteLoaderTaskKind kind, {
    List<String> installedAsiNames = const [],
    NteBundledMod? bundledMod,
    bool bundledEnabled = false,
  }) async {
    // The helper is a separate process, so it cannot read the asset bundle.
    // Extracting here means it only ever works with plain files.
    await _extractAssets();

    return NteLoaderTaskRunner.run(
      NteLoaderTask(
        kind: kind,
        gameRoot: gameRoot,
        edition: edition,
        assetRoot: source.rootPath,
        installedAsiNames: installedAsiNames,
        bundledMod: bundledMod,
        bundledEnabled: bundledEnabled,
      ),
    );
  }

  Future<void> _extractAssets() async {
    const assets = [
      NteLoaderInstaller.loaderAsiAsset,
      NteLoaderInstaller.subloaderAsset,
      NteLoaderInstaller.proxyDllAsset,
      'assets/nte_bundled/Anticensor/Anticensor.asi',
      'assets/nte_bundled/Hide_UID/Hide_UID_P.pak',
      'assets/nte_bundled/Hide_UID/Hide_UID_P.ucas',
      'assets/nte_bundled/Hide_UID/Hide_UID_P.utoc',
    ];

    for (final asset in assets) {
      await source.resolve(asset);
    }
  }
}
