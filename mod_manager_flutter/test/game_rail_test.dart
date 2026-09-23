import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/games/game_icon_store.dart';
import 'package:modlinq/games/game_rail.dart';
import 'package:modlinq/games/game_registry.dart';
import 'package:modlinq/models/game_type.dart';

void main() {
  group('rail layout', () {
    List<String> keysOf(GameRailGroup group) =>
        group.games.map((g) => g.key).toList();

    test('without settings every game sits in one unnamed group', () {
      final groups = GameRail.layout(modules: GameRegistry.modules);

      expect(groups.length, 1);
      expect(groups.single.name, isNull);
      expect(groups.single.isFavorites, isFalse);
      expect(keysOf(groups.single), ['zzz', 'ww', 'nte', 'deadlock']);
    });

    test('favourites come first, in their own group', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        favorites: ['nte', 'deadlock'],
      );

      expect(groups.first.isFavorites, isTrue);
      expect(keysOf(groups.first), ['nte', 'deadlock']);
      expect(keysOf(groups.last), ['zzz', 'ww']);
    });

    test('categories become their own groups, sorted by name', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        categories: {'zzz': 'Gacha', 'ww': 'Gacha', 'deadlock': 'Source 2'},
      );

      expect(groups.map((g) => g.name).toList(), ['Gacha', 'Source 2', null]);
      expect(keysOf(groups.first), ['zzz', 'ww']);
      expect(keysOf(groups.last), ['nte']);
    });

    test('a favourite is not listed again in its category', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        favorites: ['zzz'],
        categories: {'zzz': 'Gacha', 'ww': 'Gacha'},
      );

      expect(keysOf(groups.first), ['zzz']);
      expect(
        groups.where((g) => g.name == 'Gacha').single.games.map((g) => g.key),
        ['ww'],
      );
    });

    test('a custom order is respected inside every group', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        order: ['nte', 'deadlock', 'ww', 'zzz'],
      );

      expect(keysOf(groups.single), ['nte', 'deadlock', 'ww', 'zzz']);
    });

    test('a game missing from the order keeps its default place at the end', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        order: ['deadlock'],
      );

      expect(keysOf(groups.single).first, 'deadlock');
      expect(keysOf(groups.single).length, GameRegistry.modules.length);
    });

    test('hidden games drop out of the rail entirely', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        hidden: ['ww', 'nte'],
      );

      expect(keysOf(groups.single), ['zzz', 'deadlock']);
    });

    test('keys that match no game are ignored', () {
      final groups = GameRail.layout(
        modules: GameRegistry.modules,
        favorites: ['minecraft'],
        order: ['minecraft'],
      );

      expect(groups.single.games.length, GameRegistry.modules.length);
    });
  });

  group('icon store', () {
    late Directory tmp;
    late GameIconStore store;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('modlinq-icons');
      store = GameIconStore(tmp.path);
    });

    tearDown(() => tmp.deleteSync(recursive: true));

    test('no custom icon by default', () {
      expect(store.hasCustomIcon(GameType.zzz), isFalse);
      expect(store.iconPathFor(GameType.zzz), isNull);
    });

    test('a saved icon is found again', () async {
      await store.setIcon(GameType.zzz, [1, 2, 3]);

      expect(store.hasCustomIcon(GameType.zzz), isTrue);
      expect(File(store.iconPathFor(GameType.zzz)!).readAsBytesSync(), [1, 2, 3]);
    });

    test('replacing an icon keeps exactly one file per game', () async {
      await store.setIcon(GameType.zzz, [1], extension: 'png');
      await store.setIcon(GameType.zzz, [2], extension: 'jpg');

      final files = tmp.listSync().map((f) => p.basename(f.path)).toList();
      expect(files.where((f) => f.startsWith('zzz.')).length, 1);
      expect(File(store.iconPathFor(GameType.zzz)!).readAsBytesSync(), [2]);
    });

    test('clearing falls back to the bundled icon', () async {
      await store.setIcon(GameType.zzz, [1]);

      await store.clearIcon(GameType.zzz);

      expect(store.hasCustomIcon(GameType.zzz), isFalse);
      expect(store.iconPathFor(GameType.zzz), isNull);
    });

    test('a fetched icon is used until the user sets their own', () async {
      await store.saveAutoIcon(GameType.zzz, [9]);

      expect(store.hasCustomIcon(GameType.zzz), isFalse);
      expect(store.effectiveIconPath(GameType.zzz), store.autoIconPathFor(GameType.zzz));

      await store.setIcon(GameType.zzz, [1]);

      expect(store.effectiveIconPath(GameType.zzz), store.iconPathFor(GameType.zzz));
    });

    test('resetting falls back to the fetched icon, not to nothing', () async {
      await store.saveAutoIcon(GameType.zzz, [9]);
      await store.setIcon(GameType.zzz, [1]);

      await store.clearIcon(GameType.zzz);

      expect(store.effectiveIconPath(GameType.zzz), isNotNull);
      expect(store.hasCustomIcon(GameType.zzz), isFalse);
    });

    test('clearing a game without a custom icon is not an error', () async {
      expect(() => store.clearIcon(GameType.nte), returnsNormally);
    });
  });
}
