import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../games/game_module.dart';
import '../games/game_registry.dart';
import '../services/api_service.dart';
import '../services/app_log.dart';
import '../services/archive_service.dart';
import '../services/gamebanana_client.dart';
import '../services/marketplace_queue.dart';
import '../utils/state_providers.dart';

/// Browses GameBanana inside the app.
///
/// The catalogue is read through the public API, so the grid looks like the
/// rest of the app, downloads are verified against the published checksum, and
/// paging goes all the way through the catalogue instead of stopping after one
/// screenful. Installs run in an app-wide queue, which keeps them alive when
/// this screen goes away.
class MarketplaceScreen extends ConsumerStatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  ConsumerState<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends ConsumerState<MarketplaceScreen> {
  final GameBananaClient _client = GameBananaClient();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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

  /// Resolved once, while the widget is still mounted: `ref` is unusable
  /// from dispose(), and the listener has to come off there.
  late final MarketplaceQueue _queue = ref.read(marketplaceQueueProvider);

  GameModule get _game => GameRegistry.of(ref.read(selectedGameProvider));

  static const Map<String, String> _sortLabels = {
    GameBananaClient.sortNewest: 'Newest',
    GameBananaClient.sortMostLiked: 'Most liked',
    GameBananaClient.sortMostDownloaded: 'Most downloaded',
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _queue.addListener(_onQueueChanged);
    _load();
  }

  @override
  void dispose() {
    // The queue itself is app-wide and must survive this screen.
    _queue.removeListener(_onQueueChanged);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _onQueueChanged() async {
    if (!mounted) return;

    final config = await ApiService.getConfigService();
    if (!mounted) return;

    setState(() {
      _installedIds = config.installedMarketplaceMods(_game.key).toSet();
    });
  }

  /// Loads the next page a little before the user hits the bottom, so
  /// scrolling through thousands of mods never stalls on an empty screen.
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

    final started = DateTime.now();
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

      AppLog.info(
        'Marketplace loaded ${page.mods.length} of ${page.totalCount} mods '
        'for ${_game.key} in ${DateTime.now().difference(started).inMilliseconds} ms',
        details: 'sort: $_sort, category: ${_categoryId ?? 'all'}, '
            'query: ${_query.isEmpty ? '-' : _query}',
      );
    } catch (e, stack) {
      AppLog.error('Marketplace load failed', error: e, stack: stack);
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
    } catch (e, stack) {
      AppLog.warn('Marketplace next page failed', details: '$e\n$stack');
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

  /// Grid contents after the filters that the API cannot do itself.
  ///
  /// Search results come back unsorted and unfiltered — GameBanana's search
  /// endpoint takes neither a sort nor a category — so sort and category are
  /// applied here whenever a query is active. The 18+ filter is always local,
  /// because the only marker the API exposes is per record.
  List<GameBananaMod> get _visibleMods {
    var mods = _mods;

    if (_hideAdult) mods = mods.where((mod) => !mod.isAdult).toList();

    if (_query.isNotEmpty) {
      final category = _categoryNameOf(_categoryId);
      if (category != null) {
        mods = mods.where((mod) => mod.category == category).toList();
      }

      mods = [...mods]..sort(_compareForSort);
    }

    return mods;
  }

  int _compareForSort(GameBananaMod a, GameBananaMod b) => switch (_sort) {
    GameBananaClient.sortMostLiked => b.likes.compareTo(a.likes),
    GameBananaClient.sortMostDownloaded => b.views.compareTo(a.views),
    _ => (b.updatedAt ?? DateTime(1970)).compareTo(a.updatedAt ?? DateTime(1970)),
  };

  String? _categoryNameOf(int? id) {
    if (id == null) return null;

    for (final category in _categories) {
      if (category.id == id) return category.name;
    }
    return null;
  }

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
          _buildControls(isDarkMode),
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

  /// Sort and filter stay put while searching, because a search over 5000 mods
  /// needs them more than the unfiltered list does.
  Widget _buildControls(bool isDarkMode) {
    final activeFilters = [
      if (_categoryId != null) _categoryNameOf(_categoryId),
      if (_hideAdult) 'no 18+',
    ].whereType<String>().toList();

    return Row(
      children: [
        PopupMenuButton<String>(
          initialValue: _sort,
          tooltip: 'Sort by',
          onSelected: (value) {
            setState(() => _sort = value);
            // A server-side sort needs a fresh page; a search is sorted here.
            _query.isEmpty ? _load() : setState(() {});
          },
          itemBuilder: (context) => [
            for (final entry in _sortLabels.entries)
              PopupMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          child: _controlChip(
            icon: Icons.sort_rounded,
            label: 'Sort by: ${_sortLabels[_sort]}',
            isDarkMode: isDarkMode,
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<String>(
          tooltip: 'Filter',
          onSelected: _onFilterSelected,
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'category:',
              child: _checkableRow('All categories', _categoryId == null),
            ),
            for (final category in _categories)
              PopupMenuItem(
                value: 'category:${category.id}',
                child: _checkableRow(
                  category.name,
                  _categoryId == category.id,
                ),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'adult',
              child: _checkableRow('Hide 18+', _hideAdult),
            ),
          ],
          child: _controlChip(
            icon: Icons.filter_list_rounded,
            label: activeFilters.isEmpty
                ? 'Filter'
                : 'Filter: ${activeFilters.join(', ')}',
            isDarkMode: isDarkMode,
            isActive: activeFilters.isNotEmpty,
          ),
        ),
        const Spacer(),
        if (_query.isNotEmpty)
          Text(
            'Results for "$_query"',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
      ],
    );
  }

  void _onFilterSelected(String value) {
    if (value == 'adult') {
      setState(() => _hideAdult = !_hideAdult);
      return;
    }

    final id = value.substring('category:'.length);
    setState(() => _categoryId = id.isEmpty ? null : int.tryParse(id));

    // The index endpoint filters by category server-side; search does not.
    if (_query.isEmpty) _load();
  }

  Widget _checkableRow(String label, bool selected) => Row(
    children: [
      Icon(
        selected ? Icons.check_rounded : Icons.remove,
        size: 15,
        color: selected ? const Color(0xFF0EA5E9) : Colors.transparent,
      ),
      const SizedBox(width: 8),
      Text(label),
    ],
  );

  Widget _controlChip({
    required IconData icon,
    required String label,
    required bool isDarkMode,
    bool isActive = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: isActive
          ? const Color(0xFF0EA5E9).withValues(alpha: 0.15)
          : isDarkMode
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.black.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: isActive
            ? const Color(0xFF0EA5E9).withValues(alpha: 0.4)
            : isDarkMode
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: isActive ? const Color(0xFF38BDF8) : Colors.grey[500],
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? const Color(0xFF38BDF8) : Colors.grey[400],
          ),
        ),
        const SizedBox(width: 4),
        Icon(Icons.expand_more_rounded, size: 15, color: Colors.grey[600]),
      ],
    ),
  );

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
          _mods.isEmpty ? 'Nothing found' : 'Everything here is filtered out',
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

  /// Picks the file and confirms a flagged one here, while the user is still
  /// looking at the card. From then on the install needs no UI at all.
  Future<void> _enqueue(GameBananaMod mod) async {
    try {
      final files = await _client.files(mod.id);
      final installable = files
          .where((file) => ArchiveService.isArchiveFile(file.name))
          .toList();

      if (installable.isEmpty) {
        _snack('No supported archive attached to "${mod.name}"', isError: true);
        return;
      }

      final file = installable.first;
      if (!file.isScanClean && !await _confirmFlaggedFile(file)) return;

      AppLog.info(
        'Queued "${mod.name}" (${mod.id}) for ${_game.key}',
        details: 'file: ${file.name}, ${file.size} bytes, '
            'scan: ${file.analysisResult ?? 'unknown'}',
      );

      _queue.enqueue(mod, file, _game.key);
      if (mounted) setState(() {});
    } catch (e) {
      _snack('$e', isError: true);
    }
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
