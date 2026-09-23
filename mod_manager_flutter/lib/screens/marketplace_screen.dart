import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../games/deadlock/deadlock_manager.dart';
import '../games/game_module.dart';
import '../games/game_registry.dart';
import '../services/api_service.dart';
import '../services/archive_service.dart';
import '../services/config_service.dart';
import '../services/gamebanana_client.dart';
import '../services/marketplace_queue.dart';
import '../services/nte_mod_manager.dart';
import '../services/nte_mods_adapter.dart';
import '../utils/path_helper.dart';
import '../utils/state_providers.dart';

/// Browses GameBanana inside the app.
///
/// Replaces the embedded browser: reading the public API means the grid looks
/// like the rest of the app, downloads are verified against the published
/// checksum, files GameBanana flagged are called out, and the catalogue can be
/// paged instead of ending after one screen.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final GameBananaClient _client = GameBananaClient();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late final MarketplaceQueue _queue = MarketplaceQueue(worker: _installJob);

  List<GameBananaMod> _mods = const [];
  List<GameBananaCategory> _categories = const [];
  Set<String> _installedIds = const {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _isConfigured = true;
  int _page = 1;
  int _total = 0;
  String? _error;
  String _sort = GameBananaClient.sortNewest;
  int? _categoryId;
  String _query = '';
  bool _hideAdult = false;

  GameModule get _game => GameRegistry.of(ref.read(selectedGameProvider));

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _queue.addListener(_onQueueChanged);
    _load();
  }

  @override
  void dispose() {
    _queue.removeListener(_onQueueChanged);
    _scrollController.dispose();
    _searchController.dispose();
    _queue.dispose();
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) setState(() {});
  }

  /// Loads the next page a little before the user hits the bottom, so
  /// scrolling through 5000 mods never stalls on an empty screen.
  void _onScroll() {
    if (!_scrollController.hasClients || _isLoadingMore || !_hasMore) return;

    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 600) _loadMore();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _page = 1;
    });

    try {
      final config = await ApiService.getConfigService();
      final page = await _fetchPage(1);
      final categories = _categories.isEmpty
          ? await _client.categories(_game.marketplaceGameId)
          : _categories;

      if (!mounted) return;
      setState(() {
        _mods = page.mods;
        _total = page.totalCount;
        _hasMore = page.hasMore;
        _categories = categories;
        _installedIds = config.installedMarketplaceMods(_game.key).toSet();
        _isConfigured = _game.isConfigured(config);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);

    try {
      final page = await _fetchPage(_page + 1);
      if (!mounted) return;

      setState(() {
        _page += 1;
        // The API pages by offset, so a mod added while browsing can show up
        // twice; ids keep the grid honest.
        final known = _mods.map((mod) => mod.id).toSet();
        _mods = [
          ..._mods,
          ...page.mods.where((mod) => !known.contains(mod.id)),
        ];
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<GameBananaPage> _fetchPage(int page) => _query.isEmpty
      ? _client.index(
          gameId: _game.marketplaceGameId,
          page: page,
          sort: _sort,
          categoryId: _categoryId,
        )
      : _client.search(
          gameId: _game.marketplaceGameId,
          query: _query,
          page: page,
        );

  /// Grid contents after the client-side filters.
  ///
  /// GameBanana has no "safe only" server flag, so the 18+ filter runs here on
  /// the `_bHasContentRatings` marker the API does return.
  List<GameBananaMod> get _visibleMods =>
      _hideAdult ? _mods.where((mod) => !mod.isAdult).toList() : _mods;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(isDarkModeProvider);

    // Switching games switches catalogues; the feed must follow.
    ref.listen(selectedGameProvider, (previous, next) {
      if (previous != next) {
        setState(() {
          _categories = const [];
          _categoryId = null;
        });
        _load();
      }
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDarkMode),
          const SizedBox(height: 12),
          if (!_isConfigured) _buildNotConfiguredBanner(isDarkMode),
          _buildFilters(isDarkMode),
          const SizedBox(height: 12),
          Expanded(child: _buildBody(isDarkMode)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    final pending = _queue.pending.length;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Marketplace',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDarkMode ? Colors.grey[100] : Colors.grey[900],
                    ),
                  ),
                  if (pending > 0) ...[
                    const SizedBox(width: 10),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: Text(
                        '$pending in queue',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${_game.displayName} · ${_total > 0 ? '$_total mods' : 'GameBanana ${_game.marketplaceGameId}'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 280,
          height: 38,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search GameBanana…',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                        _load();
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            style: const TextStyle(fontSize: 12),
            onSubmitted: (value) {
              setState(() => _query = value.trim());
              _load();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNotConfiguredBanner(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_off_rounded, size: 17, color: Colors.orange[700]),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Browsing works, installing does not: set the ${_game.displayName} '
              'folder in Settings first.',
              style: TextStyle(fontSize: 12, color: Colors.orange[700]),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(tabIndexProvider.notifier).setValue(2),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(bool isDarkMode) {
    if (_query.isNotEmpty) {
      return Text(
        'Results for "$_query"',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final entry in const {
            GameBananaClient.sortNewest: 'Newest',
            GameBananaClient.sortMostLiked: 'Most liked',
            GameBananaClient.sortMostDownloaded: 'Most downloaded',
          }.entries) ...[
            ChoiceChip(
              label: Text(entry.value, style: const TextStyle(fontSize: 11)),
              selected: _sort == entry.key,
              onSelected: (_) {
                setState(() => _sort = entry.key);
                _load();
              },
            ),
            const SizedBox(width: 8),
          ],
          FilterChip(
            label: const Text('Hide 18+', style: TextStyle(fontSize: 11)),
            selected: _hideAdult,
            onSelected: (value) => setState(() => _hideAdult = value),
          ),
          const SizedBox(width: 8),
          if (_categories.isNotEmpty) ...[
            const SizedBox(width: 4),
            Container(width: 1, height: 22, color: Colors.grey.withValues(alpha: 0.25)),
            const SizedBox(width: 12),
            ChoiceChip(
              label: const Text('All', style: TextStyle(fontSize: 11)),
              selected: _categoryId == null,
              onSelected: (_) {
                setState(() => _categoryId = null);
                _load();
              },
            ),
            const SizedBox(width: 8),
            for (final category in _categories) ...[
              ChoiceChip(
                label: Text(category.name, style: const TextStyle(fontSize: 11)),
                selected: _categoryId == category.id,
                onSelected: (_) {
                  setState(() => _categoryId = category.id);
                  _load();
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBody(bool isDarkMode) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off_rounded, size: 34, color: Colors.grey[600]),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final mods = _visibleMods;

    if (mods.isEmpty) {
      return Center(
        child: Text(
          _mods.isEmpty ? 'Nothing found' : 'Everything here is 18+',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 230,
        mainAxisExtent: 236,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      // One extra cell carries the "loading more" spinner.
      itemCount: mods.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= mods.length) {
          return const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        return _buildCard(mods[index], isDarkMode);
      },
    );
  }

  Widget _buildCard(GameBananaMod mod, bool isDarkMode) {
    final job = _queue.jobFor(mod.id, _game.key);
    final isInstalled =
        _installedIds.contains('${mod.id}') ||
        job?.status == MarketplaceJobStatus.done;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF111114) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInstalled
              ? const Color(0xFF10B981).withValues(alpha: 0.5)
              : isDarkMode
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              SizedBox(
                height: 112,
                width: double.infinity,
                child: mod.thumbnailUrl == null
                    ? Container(
                        color: Colors.black.withValues(alpha: 0.2),
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.grey[700],
                        ),
                      )
                    : Image.network(
                        mod.thumbnailUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
              ),
              if (isInstalled)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _badge('Installed', const Color(0xFF10B981)),
                ),
              if (mod.isAdult)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _badge('18+', Colors.pink.shade700),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mod.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.grey[200] : Colors.grey[900],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '@${mod.author}${mod.likes > 0 ? '  ♥ ${mod.likes}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 29,
                  child: _buildInstallButton(mod, job, isInstalled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: Colors.white,
      ),
    ),
  );

  Widget _buildInstallButton(
    GameBananaMod mod,
    MarketplaceJob? job,
    bool isInstalled,
  ) {
    final status = job?.status;

    if (status == MarketplaceJobStatus.queued ||
        status == MarketplaceJobStatus.running) {
      final progress = job?.progress;
      final label = status == MarketplaceJobStatus.queued
          ? 'Queued'
          : progress == null
          ? 'Installing…'
          : '${(progress * 100).round()}%';

      return OutlinedButton.icon(
        onPressed: null,
        icon: SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2, value: progress),
        ),
        label: Text(label, style: const TextStyle(fontSize: 11)),
      );
    }

    if (status == MarketplaceJobStatus.failed) {
      return OutlinedButton.icon(
        onPressed: () => _enqueue(mod),
        icon: const Icon(Icons.refresh_rounded, size: 15),
        label: const Text('Retry', style: TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(foregroundColor: Colors.red[400]),
      );
    }

    if (isInstalled) {
      return OutlinedButton.icon(
        onPressed: () => _enqueue(mod),
        icon: const Icon(Icons.check_rounded, size: 15),
        label: const Text('Installed', style: TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF10B981),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: !mod.hasFiles || !_isConfigured ? null : () => _enqueue(mod),
      icon: const Icon(Icons.download_rounded, size: 15),
      label: Text(
        mod.hasFiles ? 'Install' : 'No files',
        style: const TextStyle(fontSize: 11),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0EA5E9),
        foregroundColor: Colors.white,
      ),
    );
  }

  void _enqueue(GameBananaMod mod) {
    if (!_queue.enqueue(mod, _game.key)) return;
    setState(() {});
  }

  /// Runs one queued install: pick a file, download it, verify it, hand it to
  /// the game's installer, then keep the thumbnail as the mod's preview.
  Future<String> _installJob(
    MarketplaceJob job,
    void Function(double) onProgress,
  ) async {
    final mod = job.mod;
    final files = await _client.files(mod.id);
    final installable = files
        .where((file) => ArchiveService.isArchiveFile(file.name))
        .toList();

    if (installable.isEmpty) {
      throw StateError('No supported archive attached');
    }

    final file = installable.first;
    if (!file.isScanClean && !await _confirmFlaggedFile(file)) {
      throw StateError('Cancelled: flagged by GameBanana');
    }

    final archive = await _download(file, onProgress);

    if (!await _checksumMatches(archive, file)) {
      await archive.delete();
      throw StateError('Checksum mismatch');
    }

    final installedName = await _importArchive(archive, mod);

    final config = await ApiService.getConfigService();
    await config.setMarketplaceInstalled(job.gameKey, mod.id, true);
    await _savePreview(mod, installedName, config);

    if (mounted) {
      setState(() => _installedIds = {..._installedIds, '${mod.id}'});
      _snack('"$installedName" installed');
    }

    return installedName;
  }

  /// GameBanana scans uploads; a non-ok verdict is worth a stop, not a block.
  Future<bool> _confirmFlaggedFile(GameBananaFile file) async {
    if (!mounted) return false;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Flagged by GameBanana'),
        content: Text(
          '${file.name} was classified as "${file.analysisResult}". That is '
          'often harmless, a bundled .exe for example, but it can also be '
          'malware.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Download anyway'),
          ),
        ],
      ),
    );

    return proceed ?? false;
  }

  Future<File> _download(
    GameBananaFile file,
    void Function(double) onProgress,
  ) async {
    final dir = await Directory.systemTemp.createTemp('modlinq-marketplace');
    final target = File(path.join(dir.path, file.name));

    final request = http.Request('GET', Uri.parse(file.downloadUrl));
    request.headers['User-Agent'] = 'modlinq-marketplace';

    final response = await http.Client().send(request);
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

  /// Routes the archive to whichever installer the selected game uses.
  Future<String> _importArchive(File archive, GameBananaMod mod) async {
    final config = await ApiService.getConfigService();
    final game = ref.read(selectedGameProvider);

    if (game.usesPakMods) {
      final FileModManager? manager = game.key == 'deadlock'
          ? DeadlockModManager.fromConfig(config)
          : NteModManager.fromConfig(config);

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
  /// Most archives ship no picture, so a freshly installed mod used to show up
  /// as a grey tile even though the store page had artwork.
  Future<void> _savePreview(
    GameBananaMod mod,
    String installedName,
    ConfigService config,
  ) async {
    final url = mod.thumbnailUrl;
    if (url == null) return;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return;

      final game = ref.read(selectedGameProvider);

      if (game.usesPakMods) {
        final FileModManager? manager = game.key == 'deadlock'
            ? DeadlockModManager.fromConfig(config)
            : NteModManager.fromConfig(config);

        manager?.setPreviewImage(
          installedName,
          response.bodyBytes,
          extension: path.extension(url).replaceFirst('.', '').toLowerCase(),
        );
        return;
      }

      // ZZZ and WW read a user image from the app's mod-images folder, which
      // takes priority over whatever the archive contained.
      final target = File(
        path.join(PathHelper.getModImagesPath(), '$installedName.png'),
      );
      target.parent.createSync(recursive: true);
      await target.writeAsBytes(response.bodyBytes, flush: true);
    } catch (_) {
      // A missing preview is cosmetic; never fail an install over it.
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[700] : null,
      ),
    );
  }
}
