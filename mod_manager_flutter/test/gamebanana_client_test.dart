import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:modlinq/services/gamebanana_client.dart';

/// Shaped like the real `Subfeed` response, trimmed to the fields used.
Map<String, dynamic> _feed() => {
  '_aMetadata': {'_nRecordCount': 2},
  '_aRecords': [
    {
      '_idRow': 719772,
      '_sModelName': 'Mod',
      '_sName': "Splatoon 3's Smallfry",
      '_sProfileUrl': 'https://gamebanana.com/mods/719772',
      '_tsDateAdded': 1790095309,
      '_tsDateModified': 1790095400,
      '_bHasFiles': true,
      '_aSubmitter': {'_sName': 'Yellowsunflower01'},
      '_aRootCategory': {'_sName': 'Skins'},
      '_aPreviewMedia': {
        '_aImages': [
          {
            '_sBaseUrl': 'https://images.gamebanana.com/img/ss/mods',
            '_sFile': '6ab2afa6a79d4.jpg',
            '_sFile220': '220-90_6ab2afa6a79d4.jpg',
          },
        ],
      },
    },
    {
      '_idRow': 4242,
      '_sModelName': 'Tutorial',
      '_sName': 'How to install',
      '_sProfileUrl': 'https://gamebanana.com/tuts/4242',
      '_bHasFiles': false,
      '_aSubmitter': {'_sName': 'someone'},
      '_aPreviewMedia': {'_aImages': []},
    },
  ],
};

void main() {
  group('feed', () {
    test('maps a record to a mod, thumbnail included', () async {
      final client = GameBananaClient(
        client: MockClient((_) async => http.Response(jsonEncode(_feed()), 200)),
      );

      final mods = await client.feed(gameId: 20948);

      expect(mods.single.id, 719772);
      expect(mods.single.name, "Splatoon 3's Smallfry");
      expect(mods.single.author, 'Yellowsunflower01');
      expect(mods.single.category, 'Skins');
      expect(
        mods.single.thumbnailUrl,
        'https://images.gamebanana.com/img/ss/mods/220-90_6ab2afa6a79d4.jpg',
      );
      expect(mods.single.updatedAt?.year, greaterThan(2020));
    });

    test('drops everything that is not a mod', () async {
      final client = GameBananaClient(
        client: MockClient((_) async => http.Response(jsonEncode(_feed()), 200)),
      );

      final mods = await client.feed(gameId: 20948);

      expect(mods.length, 1);
    });

    test('asks for the requested game, page and sort', () async {
      late Uri seen;
      final client = GameBananaClient(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(_feed()), 200);
        }),
      );

      await client.feed(gameId: 23012, page: 3, sort: 'popular');

      expect(seen.path, '/apiv11/Game/23012/Subfeed');
      expect(seen.queryParameters['_nPage'], '3');
      expect(seen.queryParameters['_sSort'], 'popular');
    });

    test('an api error is surfaced, not swallowed', () async {
      final client = GameBananaClient(
        client: MockClient((_) async => http.Response('nope', 503)),
      );

      expect(
        () => client.feed(gameId: 20948),
        throwsA(isA<http.ClientException>()),
      );
    });
  });

  group('index', () {
    Map<String, dynamic> indexPage({int total = 120}) => {
      '_aMetadata': {'_nRecordCount': total, '_nPerpage': 50},
      '_aRecords': [
        {
          '_idRow': 1,
          '_sModelName': 'Mod',
          '_sName': 'Censor Remover',
          '_sProfileUrl': 'https://gamebanana.com/mods/1',
          '_bHasFiles': true,
          '_nLikeCount': 7142,
          '_nViewCount': 900000,
          '_bHasContentRatings': true,
          '_aSubmitter': {'_sName': 'someone'},
          '_aRootCategory': {'_sName': 'Character Skins'},
          '_aPreviewMedia': {'_aImages': []},
        },
      ],
    };

    test('asks the index endpoint with game, sort and paging', () async {
      late Uri seen;
      final client = GameBananaClient(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(indexPage()), 200);
        }),
      );

      await client.index(
        gameId: 19567,
        page: 2,
        sort: GameBananaClient.sortMostLiked,
      );

      expect(seen.path, '/apiv11/Mod/Index');
      expect(seen.queryParameters['_aFilters[Generic_Game]'], '19567');
      expect(seen.queryParameters['_nPage'], '2');
      expect(seen.queryParameters['_nPerpage'], '50');
      expect(seen.queryParameters['_sSort'], 'Generic_MostLiked');
    });

    test('adds a category filter only when one is picked', () async {
      late Uri seen;
      final client = GameBananaClient(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(indexPage()), 200);
        }),
      );

      await client.index(gameId: 19567);
      expect(seen.queryParameters.containsKey('_aFilters[Generic_Category]'), isFalse);

      await client.index(gameId: 19567, categoryId: 30395);
      expect(seen.queryParameters['_aFilters[Generic_Category]'], '30395');
    });

    test('carries likes, views and the adult flag', () async {
      final client = GameBananaClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(indexPage()), 200),
        ),
      );

      final page = await client.index(gameId: 19567);

      expect(page.mods.single.likes, 7142);
      expect(page.mods.single.views, 900000);
      expect(page.mods.single.isAdult, isTrue);
    });

    test('knows whether another page exists', () async {
      final client = GameBananaClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(indexPage(total: 120)), 200),
        ),
      );

      expect((await client.index(gameId: 1, page: 1)).hasMore, isTrue);
      expect((await client.index(gameId: 1, page: 3)).hasMore, isFalse);
    });
  });

  group('game profile', () {
    Map<String, dynamic> profile() => {
      '_aPreviewMedia': {
        '_aImages': [
          {'_sType': 'banner', '_sUrl': 'https://img/banner.jpg'},
          {'_sType': 'icon', '_sUrl': 'https://img/icon.png'},
        ],
      },
      '_aModRootCategories': [
        {'_idRow': 30305, '_sName': 'Character Skins'},
        {'_idRow': 30395, '_sName': 'UI'},
      ],
    };

    test('reads the category list', () async {
      final client = GameBananaClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(profile()), 200),
        ),
      );

      final categories = await client.categories(19567);

      expect(categories.map((c) => c.name), ['Character Skins', 'UI']);
      expect(categories.first.id, 30305);
    });

    test('prefers the game icon over the promo banner', () async {
      final client = GameBananaClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(profile()), 200),
        ),
      );

      expect(await client.gameArtworkUrl(19567), 'https://img/icon.png');
    });

    test('falls back to the banner when a game has no icon', () async {
      final client = GameBananaClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              '_aPreviewMedia': {
                '_aImages': [
                  {'_sType': 'banner', '_sUrl': 'https://img/banner.jpg'},
                ],
              },
            }),
            200,
          ),
        ),
      );

      expect(await client.gameArtworkUrl(19567), 'https://img/banner.jpg');
    });

    test('a game without artwork returns null', () async {
      final client = GameBananaClient(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(await client.gameArtworkUrl(19567), isNull);
    });
  });

  group('search', () {
    test('scopes the query to one game', () async {
      late Uri seen;
      final client = GameBananaClient(
        client: MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode(_feed()), 200);
        }),
      );

      await client.search(gameId: 20948, query: 'neon skin');

      expect(seen.queryParameters['_idGameRow'], '20948');
      expect(seen.queryParameters['_sSearchString'], 'neon skin');
      expect(seen.queryParameters['_sModelName'], 'Mod');
    });
  });

  group('files', () {
    Map<String, dynamic> downloadPage() => {
      '_aFiles': [
        {
          '_sFile': 'skin.zip',
          '_nFilesize': 2407489,
          '_sDownloadUrl': 'https://gamebanana.com/dl/1823738',
          '_sMd5Checksum': '12293c0446949cb941e8f8573df0a9ee',
          '_sAnalysisResult': 'ok',
        },
        {
          '_sFile': 'sketchy.7z',
          '_nFilesize': 42,
          '_sDownloadUrl': 'https://gamebanana.com/dl/2',
          '_sAnalysisResult': 'contains_executable',
        },
      ],
    };

    test('carries checksum and scan verdict', () async {
      final client = GameBananaClient(
        client: MockClient(
          (_) async => http.Response(jsonEncode(downloadPage()), 200),
        ),
      );

      final files = await client.files(719772);

      expect(files.first.name, 'skin.zip');
      expect(files.first.md5, '12293c0446949cb941e8f8573df0a9ee');
      expect(files.first.isScanClean, isTrue);
      expect(files.last.isScanClean, isFalse);
    });

    test('a mod without files returns an empty list', () async {
      final client = GameBananaClient(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(await client.files(1), isEmpty);
    });
  });
}
