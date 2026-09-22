import 'game_module.dart';

/// One block in the game rail: either the favourites, a user category, or the
/// leftovers that belong to neither.
class GameRailGroup {
  /// Category name, or null for favourites and for uncategorised games.
  final String? name;

  final bool isFavorites;
  final List<GameModule> games;

  const GameRailGroup({
    required this.games,
    this.name,
    this.isFavorites = false,
  });
}

/// Turns the user's rail settings into the groups the sidebar renders.
///
/// Kept as a pure function: ordering rules are where this kind of feature
/// usually rots, and they are much easier to pin down in tests than in a
/// widget.
class GameRail {
  const GameRail._();

  static List<GameRailGroup> layout({
    required List<GameModule> modules,
    List<String> order = const [],
    List<String> favorites = const [],
    Map<String, String> categories = const {},
    List<String> hidden = const [],
  }) {
    final visible = modules
        .where((module) => !hidden.contains(module.key))
        .toList();

    final sorted = _sortByOrder(visible, order);

    final favoriteGames = sorted
        .where((module) => favorites.contains(module.key))
        .toList();
    final rest = sorted
        .where((module) => !favorites.contains(module.key))
        .toList();

    final groups = <GameRailGroup>[
      if (favoriteGames.isNotEmpty)
        GameRailGroup(games: favoriteGames, isFavorites: true),
    ];

    final byCategory = <String, List<GameModule>>{};
    final uncategorised = <GameModule>[];

    for (final module in rest) {
      final category = categories[module.key];
      if (category == null || category.isEmpty) {
        uncategorised.add(module);
      } else {
        byCategory.putIfAbsent(category, () => []).add(module);
      }
    }

    final categoryNames = byCategory.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    for (final name in categoryNames) {
      groups.add(GameRailGroup(name: name, games: byCategory[name]!));
    }

    if (uncategorised.isNotEmpty) {
      groups.add(GameRailGroup(games: uncategorised));
    }

    return groups;
  }

  /// Games named in [order] come first in that order; everything else keeps
  /// its registry position behind them, so a partial order is still valid.
  static List<GameModule> _sortByOrder(
    List<GameModule> modules,
    List<String> order,
  ) {
    if (order.isEmpty) return modules;

    final ranked = [...modules];
    ranked.sort((a, b) {
      final ra = order.indexOf(a.key);
      final rb = order.indexOf(b.key);

      if (ra == -1 && rb == -1) return modules.indexOf(a) - modules.indexOf(b);
      if (ra == -1) return 1;
      if (rb == -1) return -1;
      return ra - rb;
    });

    return ranked;
  }
}
