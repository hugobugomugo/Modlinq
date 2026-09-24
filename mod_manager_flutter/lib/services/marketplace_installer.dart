import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../games/deadlock/deadlock_manager.dart';
import '../models/game_type.dart';
import '../utils/path_helper.dart';
import 'api_service.dart';
import 'app_log.dart';
import 'archive_service.dart';
import 'config_service.dart';
import 'gamebanana_client.dart';
import 'marketplace_queue.dart';
import 'nte_mod_manager.dart';
import 'nte_mods_adapter.dart';

/// Downloads and installs one marketplace mod.
///
/// Deliberately free of any widget or BuildContext: installs used to live in
/// the marketplace screen's state, so leaving the tab disposed them and killed
/// the download. Everything the install needs is decided before it starts.
class MarketplaceInstaller {
  final http.Client _client;

  MarketplaceInstaller({http.Client? client})
    : _client = client ?? http.Client();

  /// Runs [job] and returns the name the mod ended up with in the library.
  Future<String> install(
    MarketplaceJob job,
    void Function(double progress) onProgress,
  ) async {
    final started = DateTime.now();
    AppLog.info('Installing "${job.mod.name}" for ${job.gameKey}');

    final archive = await _download(job.file, onProgress);

    if (!await _checksumMatches(archive, job.file)) {
      await archive.delete();
      throw StateError('Checksum mismatch, install aborted');
    }

    final config = await ApiService.getConfigService();
    final game = GameTypeX.fromKey(job.gameKey);

    final installedName = await _importArchive(archive, game, config);

    await config.setMarketplaceInstalled(job.gameKey, job.mod.id, true);
    await _savePreview(job.mod, installedName, game, config);

    AppLog.info(
      'Installed "$installedName" in '
      '${DateTime.now().difference(started).inMilliseconds} ms',
    );

    return installedName;
  }

  Future<File> _download(
    GameBananaFile file,
    void Function(double) onProgress,
  ) async {
    final dir = await Directory.systemTemp.createTemp('modlinq-marketplace');
    final target = File(p.join(dir.path, file.name));

    final request = http.Request('GET', Uri.parse(file.downloadUrl));
    request.headers['User-Agent'] = 'modlinq-marketplace';

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw http.ClientException('Download failed (${response.statusCode})');
    }

    final total = response.contentLength ?? file.size;
    var received = 0;
    final sink = target.openWrite();

    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (total > 0) onProgress(received / total);
    }
    await sink.close();

    return target;
  }

  /// GameBanana publishes an md5 per file; a truncated download fails here
  /// instead of producing a broken mod folder.
  Future<bool> _checksumMatches(File archive, GameBananaFile file) async {
    final expected = file.md5;
    if (expected == null || expected.isEmpty) return true;

    final digest = await md5.bind(archive.openRead()).first;
    return digest.toString().toLowerCase() == expected.toLowerCase();
  }

  /// Routes the archive to whichever installer the game uses.
  Future<String> _importArchive(
    File archive,
    GameType game,
    ConfigService config,
  ) async {
    if (game.usesPakMods) {
      final manager = _fileManagerFor(game, config);
      if (manager == null) {
        throw StateError('Set the game folder in settings first');
      }

      final skipped = <String, String>{};
      final imported = await manager.import([archive.path], skipped: skipped);

      if (imported.isEmpty) {
        throw StateError(skipped.values.firstOrNull ?? 'Nothing imported');
      }

      return imported.first.name;
    }

    // 3DMigoto games: unpack, then hand the folders to the existing importer.
    final extraction = await ArchiveService.extractArchive(archiveFile: archive);
    if (!extraction.success) {
      throw StateError(extraction.error ?? 'Archive format not supported');
    }

    final folders = extraction.extractedFolders ?? const [];
    if (folders.isEmpty) throw StateError('The archive held no mod folder');

    final modManager = await ApiService.getModManagerService();
    final (imported, _) = await modManager.importMods(folders);

    if (imported.isEmpty) throw StateError('Mod was already there');

    return imported.first;
  }

  /// Keeps the marketplace thumbnail as the mod's preview image.
  ///
  /// Most archives ship no picture, so a freshly installed mod would show up
  /// as a grey tile even though the store page had artwork.
  Future<void> _savePreview(
    GameBananaMod mod,
    String installedName,
    GameType game,
    ConfigService config,
  ) async {
    final url = mod.thumbnailUrl;
    if (url == null) return;

    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200) return;

      if (game.usesPakMods) {
        _fileManagerFor(game, config)?.setPreviewImage(
          installedName,
          response.bodyBytes,
          extension: p.extension(url).replaceFirst('.', '').toLowerCase(),
        );
        return;
      }

      // ZZZ and WW read a user image from the app's mod-images folder, which
      // takes priority over whatever the archive contained.
      final target = File(
        p.join(PathHelper.getModImagesPath(), '$installedName.png'),
      );
      target.parent.createSync(recursive: true);
      await target.writeAsBytes(response.bodyBytes, flush: true);
    } catch (_) {
      // A missing preview is cosmetic; never fail an install over it.
    }
  }

  FileModManager? _fileManagerFor(GameType game, ConfigService config) =>
      switch (game) {
        GameType.deadlock => DeadlockModManager.fromConfig(config),
        GameType.nte => NteModManager.fromConfig(config),
        _ => null,
      };
}
