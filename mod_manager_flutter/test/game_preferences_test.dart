import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ConfigService config;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('modlinq-prefs');
    config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  group('rail preferences', () {
    test('order, favourites and hidden games round trip', () async {
      await config.setGameOrder(['nte', 'zzz']);
      await config.setGameFavorites(['nte']);
      await config.setHiddenGames(['ww']);

      expect(config.gameOrder, ['nte', 'zzz']);
      expect(config.gameFavorites, ['nte']);
      expect(config.hiddenGames, ['ww']);
    });

    test('categories are set and cleared per game', () async {
      await config.setGameCategory('zzz', 'Gacha');
      await config.setGameCategory('deadlock', 'Source 2');

      expect(config.gameCategories, {'zzz': 'Gacha', 'deadlock': 'Source 2'});

      await config.setGameCategory('zzz', null);

      expect(config.gameCategories, {'deadlock': 'Source 2'});
    });

    test('defaults are empty, not null', () {
      expect(config.gameOrder, isEmpty);
      expect(config.gameFavorites, isEmpty);
      expect(config.gameCategories, isEmpty);
      expect(config.hiddenGames, isEmpty);
    });
  });

  group('marketplace installs', () {
    test('an installed gamebanana id is remembered per game', () async {
      await config.setMarketplaceInstalled('zzz', 719772, true);

      expect(config.installedMarketplaceMods('zzz'), ['719772']);
      expect(config.installedMarketplaceMods('nte'), isEmpty);
    });

    test('installing the same mod twice keeps one entry', () async {
      await config.setMarketplaceInstalled('zzz', 1, true);
      await config.setMarketplaceInstalled('zzz', 1, true);

      expect(config.installedMarketplaceMods('zzz'), ['1']);
    });

    test('an id can be dropped again', () async {
      await config.setMarketplaceInstalled('zzz', 1, true);
      await config.setMarketplaceInstalled('zzz', 1, false);

      expect(config.installedMarketplaceMods('zzz'), isEmpty);
    });
  });

  group('hidden mods', () {
    test('hiding and unhiding a mod', () async {
      await config.setModHidden('zzz', 'Ugly Skin', true);
      expect(config.hiddenMods('zzz'), ['Ugly Skin']);

      await config.setModHidden('zzz', 'Ugly Skin', false);
      expect(config.hiddenMods('zzz'), isEmpty);
    });

    test('hiding the same mod twice keeps one entry', () async {
      await config.setModHidden('zzz', 'Skin', true);
      await config.setModHidden('zzz', 'Skin', true);

      expect(config.hiddenMods('zzz'), ['Skin']);
    });

    test('each game keeps its own list', () async {
      await config.setModHidden('zzz', 'Skin', true);
      await config.setModHidden('nte', 'Other', true);

      expect(config.hiddenMods('zzz'), ['Skin']);
      expect(config.hiddenMods('nte'), ['Other']);
      expect(config.hiddenMods('deadlock'), isEmpty);
    });
  });
}
