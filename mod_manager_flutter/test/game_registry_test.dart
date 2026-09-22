import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/games/game_registry.dart';
import 'package:modlinq/models/game_type.dart';

void main() {
  group('registry', () {
    test('covers every game the app knows', () {
      expect(
        GameRegistry.modules.map((m) => m.type).toSet(),
        GameType.values.toSet(),
      );
    });

    test('module keys stay the persisted config keys', () {
      for (final module in GameRegistry.modules) {
        expect(module.key, module.type.key);
      }
    });

    test('looks a module up by its key', () {
      expect(GameRegistry.byKey('nte')?.type, GameType.nte);
      expect(GameRegistry.byKey('deadlock')?.type, GameType.deadlock);
      expect(GameRegistry.byKey('minecraft'), isNull);
    });

    test('every game has a label and a marketplace hub', () {
      for (final module in GameRegistry.modules) {
        expect(module.shortLabel, isNotEmpty);
        expect(module.displayName, isNotEmpty);
        expect(module.marketplaceGameId, greaterThan(0));
      }
    });
  });

  group('capabilities', () {
    test('character grids are for the gacha games only', () {
      expect(GameRegistry.of(GameType.zzz).caps.hasCharacters, isTrue);
      expect(GameRegistry.of(GameType.wutheringWaves).caps.hasCharacters, isTrue);
      expect(GameRegistry.of(GameType.nte).caps.hasCharacters, isFalse);
    });

    test('pak mods and the loader belong to nte', () {
      expect(GameRegistry.of(GameType.nte).caps.usesPakMods, isTrue);
      expect(GameRegistry.of(GameType.nte).caps.needsLoader, isTrue);
      expect(GameRegistry.of(GameType.zzz).caps.usesPakMods, isFalse);
      expect(GameRegistry.of(GameType.zzz).caps.needsLoader, isFalse);
    });

    test('deadlock copies archives and needs its gameinfo patched', () {
      final caps = GameRegistry.of(GameType.deadlock).caps;

      expect(caps.usesPakMods, isTrue);
      expect(caps.needsLoader, isTrue);
      expect(caps.hasCharacters, isFalse);
    });

    test('f10 reload is zzz only', () {
      expect(GameRegistry.of(GameType.zzz).caps.hasF10Reload, isTrue);
      expect(GameRegistry.of(GameType.wutheringWaves).caps.hasF10Reload, isFalse);
      expect(GameRegistry.of(GameType.nte).caps.hasF10Reload, isFalse);
      expect(GameRegistry.of(GameType.deadlock).caps.hasF10Reload, isFalse);
    });

    test('the game type getters read through to the module', () {
      expect(GameType.nte.displayName, 'Neverness to Everness');
      expect(GameType.zzz.shortLabel, 'ZZZ');
      expect(GameType.nte.hasCharacters, isFalse);
      expect(GameType.nte.usesPakMods, isTrue);
    });
  });

  group('marketplace', () {
    test('each game points at its own gamebanana hub', () {
      expect(GameRegistry.of(GameType.zzz).marketplaceGameId, 19567);
      expect(GameRegistry.of(GameType.wutheringWaves).marketplaceGameId, 20357);
      expect(GameRegistry.of(GameType.nte).marketplaceGameId, 23012);
      expect(GameRegistry.of(GameType.deadlock).marketplaceGameId, 20948);
    });

    test('hub and search urls carry the game id', () {
      final module = GameRegistry.of(GameType.nte);

      expect(module.marketplaceUrl, 'https://gamebanana.com/games/23012');
      expect(
        module.marketplaceSearchUrl('neon skin'),
        'https://gamebanana.com/search?_type=Mods&game=23012&query=neon%20skin',
      );
    });
  });
}
