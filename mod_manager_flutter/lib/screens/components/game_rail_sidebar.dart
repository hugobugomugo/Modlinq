import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;

import '../../games/game_icon_store.dart';
import '../../games/game_module.dart';
import '../../games/game_rail.dart';
import '../../games/game_registry.dart';
import '../../services/api_service.dart';
import '../../services/config_service.dart';
import '../../utils/path_helper.dart';
import '../../utils/state_providers.dart';

/// Vertical game switcher on the far left.
///
/// Games grow downwards like browser tabs instead of sharing one row, so the
/// rail stays readable no matter how many games are supported. Order,
/// favourites, categories, icons and which games show at all are the user's.
class GameRailSidebar extends ConsumerStatefulWidget {
  const GameRailSidebar({super.key});

  @override
  ConsumerState<GameRailSidebar> createState() => _GameRailSidebarState();
}

enum _RailAction { pasteIcon, pickIcon, resetIcon, toggleFavorite, category, hide }

class _GameRailSidebarState extends ConsumerState<GameRailSidebar> {
  ConfigService? _config;
  late final GameIconStore _icons = GameIconStore(
    p.join(PathHelper.getAppDataPath(), 'game_icons'),
  );

  List<String> _order = const [];
  List<String> _favorites = const [];
  List<String> _hidden = const [];
  Map<String, String> _categories = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ApiService.getConfigService();
    if (!mounted) return;

    setState(() {
      _config = config;
      _order = config.gameOrder;
      _favorites = config.gameFavorites;
      _hidden = config.hiddenGames;
      _categories = config.gameCategories;
    });
  }

  List<GameRailGroup> get _groups => GameRail.layout(
    modules: GameRegistry.modules,
    order: _order,
    favorites: _favorites,
    categories: _categories,
    hidden: _hidden,
  );

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(isDarkModeProvider);
    final selected = ref.watch(selectedGameProvider);

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF0D0D10) : Colors.grey[100],
        border: Border(
          right: BorderSide(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  for (final group in _groups) ...[
                    _buildGroupLabel(group, isDarkMode),
                    for (final module in group.games) ...[
                      _buildTile(module, selected, isDarkMode),
                      const SizedBox(height: 6),
                    ],
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
          if (_hidden.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildAddButton(isDarkMode),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupLabel(GameRailGroup group, bool isDarkMode) {
    final label = group.isFavorites ? 'FAVORITES' : group.name?.toUpperCase();
    if (label == null) return const SizedBox(height: 4);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Text(
        label,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 8,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
          color: isDarkMode ? Colors.grey[600] : Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildTile(GameModule module, GameType selected, bool isDarkMode) {
    final isActive = module.type == selected;
    final iconPath = _icons.iconPathFor(module.type);
    final isFavorite = _favorites.contains(module.key);

    return Tooltip(
      message: module.displayName,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _select(module),
          onSecondaryTapDown: (details) =>
              _showTileMenu(module, details.globalPosition),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? const LinearGradient(
                          colors: [Color(0xFF0EA5E9), Color(0xFF06B6D4)],
                        )
                      : null,
                  color: isActive
                      ? null
                      : isDarkMode
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isActive
                        ? Colors.transparent
                        : isDarkMode
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.05),
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: iconPath == null
                    ? Center(
                        child: Text(
                          module.shortLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: isActive ? Colors.white : Colors.grey[500],
                          ),
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.file(
                          File(iconPath),
                          fit: BoxFit.cover,
                          width: 52,
                          height: 52,
                          // The path is stable per game, so the cache would
                          // keep showing the previous icon after a change.
                          key: ValueKey('${module.key}-${File(iconPath).lastModifiedSync()}'),
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              module.shortLabel,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
              ),
              if (isFavorite)
                const Positioned(
                  top: -3,
                  right: -3,
                  child: Icon(Icons.star_rounded, size: 13, color: Color(0xFFFBBF24)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton(bool isDarkMode) {
    return Tooltip(
      message: 'Hidden games',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _showHiddenGamesDialog,
          child: Container(
            width: 52,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.12),
                style: BorderStyle.solid,
              ),
            ),
            child: Icon(Icons.add_rounded, size: 18, color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }

  Future<void> _select(GameModule module) async {
    if (ref.read(selectedGameProvider) == module.type) return;

    await ApiService.setCurrentGame(module.type);
  }

  Future<void> _showTileMenu(GameModule module, Offset position) async {
    final hasCustomIcon = _icons.hasCustomIcon(module.type);
    final isFavorite = _favorites.contains(module.key);

    final action = await showMenu<_RailAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem(
          value: _RailAction.pasteIcon,
          child: const Text('Icon from clipboard'),
        ),
        PopupMenuItem(
          value: _RailAction.pickIcon,
          child: const Text('Icon from file…'),
        ),
        // Only offered when there is something to undo, so the menu never
        // shows an action that would do nothing.
        if (hasCustomIcon)
          PopupMenuItem(
            value: _RailAction.resetIcon,
            child: const Text('Reset icon'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _RailAction.toggleFavorite,
          child: Text(isFavorite ? 'Remove from favorites' : 'Add to favorites'),
        ),
        PopupMenuItem(
          value: _RailAction.category,
          child: const Text('Change category…'),
        ),
        PopupMenuItem(
          value: _RailAction.hide,
          child: const Text('Hide game'),
        ),
      ],
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _RailAction.pasteIcon:
        await _setIconFromClipboard(module);
      case _RailAction.pickIcon:
        await _setIconFromFile(module);
      case _RailAction.resetIcon:
        await _icons.clearIcon(module.type);
        setState(() {});
      case _RailAction.toggleFavorite:
        await _toggleFavorite(module, !isFavorite);
      case _RailAction.category:
        await _editCategory(module);
      case _RailAction.hide:
        await _hideGame(module);
    }
  }

  Future<void> _setIconFromClipboard(GameModule module) async {
    final bytes = await Pasteboard.image;
    if (bytes == null) {
      _snack('No image in the clipboard');
      return;
    }

    await _icons.setIcon(module.type, bytes);
    _refreshImages();
  }

  Future<void> _setIconFromFile(GameModule module) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: GameIconStore.supportedExtensions,
    );

    final path = result?.files.single.path;
    if (path == null) return;

    await _icons.setIcon(
      module.type,
      await File(path).readAsBytes(),
      extension: p.extension(path).replaceFirst('.', '').toLowerCase(),
    );
    _refreshImages();
  }

  /// Flutter caches decoded images by path, and the icon path never changes.
  void _refreshImages() {
    imageCache.clear();
    imageCache.clearLiveImages();
    if (mounted) setState(() {});
  }

  Future<void> _toggleFavorite(GameModule module, bool favorite) async {
    final config = _config;
    if (config == null) return;

    final favorites = _favorites.toSet();
    favorite ? favorites.add(module.key) : favorites.remove(module.key);

    await config.setGameFavorites(favorites.toList());
    await _load();
  }

  Future<void> _hideGame(GameModule module) async {
    final config = _config;
    if (config == null) return;

    await config.setHiddenGames({..._hidden, module.key}.toList());

    // Never leave the user staring at a game that is no longer in the rail.
    if (ref.read(selectedGameProvider) == module.type) {
      final fallback = GameRegistry.modules.firstWhere(
        (m) => m.key != module.key,
        orElse: () => module,
      );
      await ApiService.setCurrentGame(fallback.type);
    }

    await _load();
  }

  Future<void> _editCategory(GameModule module) async {
    final config = _config;
    if (config == null) return;

    final controller = TextEditingController(
      text: _categories[module.key] ?? '',
    );

    final value = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Category for ${module.displayName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Gacha, Source 2',
              ),
              onSubmitted: (text) => Navigator.of(dialogContext).pop(text),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final name in _categories.values.toSet())
                  ActionChip(
                    label: Text(name),
                    onPressed: () => Navigator.of(dialogContext).pop(name),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('None'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (value == null) return;

    await config.setGameCategory(module.key, value.trim());
    await _load();
  }

  Future<void> _showHiddenGamesDialog() async {
    final config = _config;
    if (config == null) return;

    final restored = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Hidden games'),
        children: [
          for (final key in _hidden)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(key),
              child: Text(GameRegistry.byKey(key)?.displayName ?? key),
            ),
        ],
      ),
    );

    if (restored == null) return;

    await config.setHiddenGames(
      _hidden.where((key) => key != restored).toList(),
    );
    await _load();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
