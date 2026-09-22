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
import '../services/gamebanana_client.dart';
import '../services/nte_mod_manager.dart';
import '../services/nte_mods_adapter.dart';
import '../utils/state_providers.dart';

/// Browses GameBanana inside the app.
///
/// This used to be an embedded browser. Reading the public API instead means
/// the grid matches the rest of the app, the download is verified against the
/// checksum GameBanana publishes, and a file its scanner flagged can be
/// called out before anything is unpacked.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final GameBananaClient _client = GameBananaClient();
  final TextEditingController _searchController = TextEditingController();

  List<GameBananaMod> _mods = const [];
  bool _isLoading = true;
  String? _error;
  String _sort = 'new';
  String _query = '';
  int? _installingModId;

  GameModule get _game => GameRegistry.of(ref.read(selectedGameProvider));

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final mods = _query.isEmpty
          ? await _client.feed(gameId: _game.marketplaceGameId, sort: _sort)
          : await _client.search(
              gameId: _game.marketplaceGameId,
              query: _query,
            );

      if (!mounted) return;
      setState(() {
        _mods = mods;
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(isDarkModeProvider);

    // Switching games switches catalogues; the feed must follow.
    ref.listen(selectedGameProvider, (previous, next) {
      if (previous != next) _load();
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDarkMode),
          const SizedBox(height: 14),
          _buildSortChips(isDarkMode),
          const SizedBox(height: 14),
          Expanded(child: _buildBody(isDarkMode)),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Marketplace',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isDarkMode ? Colors.grey[100] : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_game.displayName} · GameBanana ${_game.marketplaceGameId}',
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
              hintText: 'GameBanana durchsuchen…',
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

  Widget _buildSortChips(bool isDarkMode) {
    if (_query.isNotEmpty) {
      return Text(
        'Suchergebnisse für "$_query"',
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        for (final entry in const {'new': 'Neu', 'default': 'Beliebt'}.entries)
          ChoiceChip(
            label: Text(entry.value, style: const TextStyle(fontSize: 11)),
            selected: _sort == entry.key,
            onSelected: (_) {
              setState(() => _sort = entry.key);
              _load();
            },
          ),
      ],
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
            OutlinedButton(onPressed: _load, child: const Text('Nochmal')),
          ],
        ),
      );
    }

    if (_mods.isEmpty) {
      return Center(
        child: Text(
          'Nichts gefunden',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 260,
        mainAxisExtent: 250,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: _mods.length,
      itemBuilder: (context, index) => _buildCard(_mods[index], isDarkMode),
    );
  }

  Widget _buildCard(GameBananaMod mod, bool isDarkMode) {
    final isInstalling = _installingModId == mod.id;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF111114) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 120,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
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
                const SizedBox(height: 4),
                Text(
                  '@${mod.author}${mod.category == null ? '' : ' · ${mod.category}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  height: 30,
                  child: ElevatedButton.icon(
                    onPressed: !mod.hasFiles || _installingModId != null
                        ? null
                        : () => _install(mod),
                    icon: isInstalling
                        ? const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 15),
                    label: Text(
                      isInstalling
                          ? 'Lädt…'
                          : mod.hasFiles
                          ? 'Installieren'
                          : 'Keine Dateien',
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _install(GameBananaMod mod) async {
    setState(() => _installingModId = mod.id);

    try {
      final files = await _client.files(mod.id);
      final installable = files
          .where((file) => ArchiveService.isArchiveFile(file.name))
          .toList();

      if (installable.isEmpty) {
        _snack('Keine unterstützte Archivdatei bei "${mod.name}"');
        return;
      }

      final file = installable.first;
      if (!file.isScanClean && !await _confirmFlaggedFile(file)) return;

      final archive = await _download(file);
      if (archive == null) return;

      if (!await _checksumMatches(archive, file)) {
        _snack('Prüfsumme stimmt nicht, Installation abgebrochen', isError: true);
        await archive.delete();
        return;
      }

      await _importArchive(archive, mod);
    } catch (e) {
      _snack('$e', isError: true);
    } finally {
      if (mounted) setState(() => _installingModId = null);
    }
  }

  /// GameBanana scans uploads; a non-ok verdict is worth a stop, not a block.
  Future<bool> _confirmFlaggedFile(GameBananaFile file) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Von GameBanana markiert'),
        content: Text(
          '${file.name} wurde als "${file.analysisResult}" eingestuft. '
          'Das ist oft harmlos (z. B. eine mitgelieferte .exe), kann aber '
          'auch Schadsoftware sein.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Trotzdem laden'),
          ),
        ],
      ),
    );

    return proceed ?? false;
  }

  Future<File?> _download(GameBananaFile file) async {
    final dir = await Directory.systemTemp.createTemp('modlinq-marketplace');
    final target = File(path.join(dir.path, file.name));

    final request = http.Request('GET', Uri.parse(file.downloadUrl));
    request.headers['User-Agent'] = 'modlinq-marketplace';

    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      _snack('Download fehlgeschlagen (${response.statusCode})', isError: true);
      return null;
    }

    final sink = target.openWrite();
    await response.stream.pipe(sink);

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
  Future<void> _importArchive(File archive, GameBananaMod mod) async {
    final config = await ApiService.getConfigService();
    final game = ref.read(selectedGameProvider);

    if (game.usesPakMods) {
      final FileModManager? manager = game.usesPakMods && game.key == 'deadlock'
          ? DeadlockModManager.fromConfig(config)
          : NteModManager.fromConfig(config);

      if (manager == null) {
        _snack('Erst den Spielordner in den Einstellungen setzen', isError: true);
        return;
      }

      final skipped = <String, String>{};
      final imported = await manager.import([archive.path], skipped: skipped);

      _snack(
        imported.isNotEmpty
            ? '"${imported.first.name}" importiert'
            : skipped.values.firstOrNull ?? 'Nichts importiert',
        isError: imported.isEmpty,
      );
      return;
    }

    // 3DMigoto games: unpack, then hand the folders to the existing importer.
    final extraction = await ArchiveService.extractArchive(archiveFile: archive);
    if (!extraction.success) {
      _snack(extraction.error ?? 'Archiv nicht unterstützt', isError: true);
      return;
    }

    final folders = extraction.extractedFolders ?? const [];
    if (folders.isEmpty) {
      _snack('Archiv enthielt keinen Mod-Ordner', isError: true);
      return;
    }

    final modManager = await ApiService.getModManagerService();
    final (imported, _) = await modManager.importMods(folders);

    _snack(
      imported.isNotEmpty
          ? '"${mod.name}" installiert'
          : 'Mod war schon vorhanden',
      isError: imported.isEmpty,
    );
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

