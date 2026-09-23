import 'dart:convert';

import 'package:http/http.dart' as http;

/// One page of results plus the total, so the UI knows when to stop asking.
class GameBananaPage {
  final List<GameBananaMod> mods;
  final int totalCount;
  final int page;
  final int perPage;

  const GameBananaPage({
    required this.mods,
    required this.totalCount,
    required this.page,
    required this.perPage,
  });

  bool get hasMore => page * perPage < totalCount;
}

/// A category a game groups its mods into, e.g. "Character Skins".
class GameBananaCategory {
  final int id;
  final String name;

  const GameBananaCategory({required this.id, required this.name});
}

/// A mod as listed by GameBanana.
class GameBananaMod {
  final int id;
  final String name;
  final String author;
  final String profileUrl;
  final String? thumbnailUrl;
  final String? category;
  final DateTime? updatedAt;

  /// Whether the submission has files at all. Pages, guides and WiPs show up
  /// in the same feed and cannot be installed.
  final bool hasFiles;

  final int likes;
  final int views;

  /// GameBanana's own "this has content ratings" flag, which in practice
  /// means adult content.
  final bool isAdult;

  const GameBananaMod({
    required this.id,
    required this.name,
    required this.author,
    required this.profileUrl,
    required this.hasFiles,
    this.thumbnailUrl,
    this.category,
    this.updatedAt,
    this.likes = 0,
    this.views = 0,
    this.isAdult = false,
  });

  static GameBananaMod fromJson(Map<String, dynamic> json) {
    final images = (json['_aPreviewMedia']?['_aImages'] as List?) ?? const [];
    final first = images.isEmpty ? null : images.first as Map<String, dynamic>;

    return GameBananaMod(
      id: (json['_idRow'] ?? 0) as int,
      name: (json['_sName'] ?? '') as String,
      author: (json['_aSubmitter']?['_sName'] ?? '') as String,
      profileUrl: (json['_sProfileUrl'] ?? '') as String,
      hasFiles: (json['_bHasFiles'] ?? false) as bool,
      // 220px variant: the grid never shows anything bigger, and the full
      // screenshots are megabytes each.
      thumbnailUrl: first == null
          ? null
          : '${first['_sBaseUrl']}/${first['_sFile220'] ?? first['_sFile']}',
      category: json['_aRootCategory']?['_sName'] as String?,
      updatedAt: _dateOf(json['_tsDateModified'] ?? json['_tsDateAdded']),
      likes: (json['_nLikeCount'] ?? 0) as int,
      views: (json['_nViewCount'] ?? 0) as int,
      isAdult: (json['_bHasContentRatings'] ?? false) as bool,
    );
  }

  static DateTime? _dateOf(Object? timestamp) => timestamp is int
      ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
      : null;
}

/// A downloadable file of a mod.
class GameBananaFile {
  final String name;
  final int size;
  final String downloadUrl;
  final String? md5;

  /// GameBanana's own scan verdict, `ok` when it found nothing.
  final String? analysisResult;

  const GameBananaFile({
    required this.name,
    required this.size,
    required this.downloadUrl,
    this.md5,
    this.analysisResult,
  });

  bool get isScanClean => analysisResult == null || analysisResult == 'ok';

  static GameBananaFile fromJson(Map<String, dynamic> json) => GameBananaFile(
    name: (json['_sFile'] ?? '') as String,
    size: (json['_nFilesize'] ?? 0) as int,
    downloadUrl: (json['_sDownloadUrl'] ?? '') as String,
    md5: json['_sMd5Checksum'] as String?,
    analysisResult: json['_sAnalysisResult'] as String?,
  );
}

/// Reads the public GameBanana API.
///
/// Replaces the embedded browser: the same catalogue, but the app can show its
/// own grid, verify checksums before unpacking and skip files GameBanana
/// flagged.
class GameBananaClient {
  final http.Client _client;

  GameBananaClient({http.Client? client}) : _client = client ?? http.Client();

  static const String base = 'https://gamebanana.com/apiv11';

  /// The Index endpoint's maximum. Fewer requests, fewer half-empty rows.
  static const int perPage = 50;

  /// Sort orders the Index endpoint understands.
  static const String sortNewest = 'Generic_LatestModified';
  static const String sortMostLiked = 'Generic_MostLiked';
  static const String sortMostDownloaded = 'Generic_MostDownloaded';

  /// The browsable catalogue: 50 per page, sortable, filterable by category.
  ///
  /// The Subfeed endpoint mixes in tutorials and WiPs and caps out at 15 per
  /// page, which is why browsing uses this one.
  Future<GameBananaPage> index({
    required int gameId,
    int page = 1,
    String sort = sortNewest,
    int? categoryId,
  }) async {
    final filters = <String, String>{
      '_aFilters[Generic_Game]': '$gameId',
      if (categoryId != null) '_aFilters[Generic_Category]': '$categoryId',
    };

    final uri = Uri.parse('$base/Mod/Index').replace(
      queryParameters: {
        '_nPage': '$page',
        '_nPerpage': '$perPage',
        '_sSort': sort,
        ...filters,
      },
    );

    final json = await _get(uri);

    return GameBananaPage(
      mods: _records(json),
      totalCount: (json['_aMetadata']?['_nRecordCount'] ?? 0) as int,
      page: page,
      perPage: perPage,
    );
  }

  /// Categories this game sorts its mods into, for the filter row.
  Future<List<GameBananaCategory>> categories(int gameId) async {
    final json = await _get(Uri.parse('$base/Game/$gameId/ProfilePage'));
    final categories = (json['_aModRootCategories'] as List?) ?? const [];

    return categories
        .cast<Map<String, dynamic>>()
        .map(
          (category) => GameBananaCategory(
            id: (category['_idRow'] ?? 0) as int,
            name: (category['_sName'] ?? '') as String,
          ),
        )
        .where((category) => category.id > 0)
        .toList();
  }

  /// The game's own icon, for the rail.
  ///
  /// GameBanana serves these at 32x32 and offers no larger variant, so the
  /// rail draws them at their native size instead of stretching them over the
  /// tile. The banner is deliberately not used: it is promo art, not the icon
  /// the user recognises.
  Future<String?> gameArtworkUrl(int gameId) async {
    final json = await _get(Uri.parse('$base/Game/$gameId/ProfilePage'));
    final images = (json['_aPreviewMedia']?['_aImages'] as List?) ?? const [];

    String? bannerUrl;
    for (final image in images.cast<Map<String, dynamic>>()) {
      if (image['_sType'] == 'icon') return image['_sUrl'] as String?;
      if (image['_sType'] == 'banner') bannerUrl ??= image['_sUrl'] as String?;
    }

    return bannerUrl;
  }

  /// Newest or most popular submissions of a game.
  Future<List<GameBananaMod>> feed({
    required int gameId,
    int page = 1,
    String sort = 'new',
  }) async {
    final uri = Uri.parse(
      '$base/Game/$gameId/Subfeed'
      '?_nPage=$page&_nPerpage=$perPage&_sSort=$sort',
    );

    return _records(await _get(uri));
  }

  /// Full-text search inside one game's mods.
  Future<GameBananaPage> search({
    required int gameId,
    required String query,
    int page = 1,
  }) async {
    final uri = Uri.parse(
      '$base/Util/Search/Results'
      '?_sModelName=Mod&_idGameRow=$gameId&_nPage=$page&_nPerpage=$perPage'
      '&_sSearchString=${Uri.encodeComponent(query)}',
    );

    final json = await _get(uri);

    return GameBananaPage(
      mods: _records(json),
      totalCount: (json['_aMetadata']?['_nRecordCount'] ?? 0) as int,
      page: page,
      perPage: perPage,
    );
  }

  /// Files attached to a mod, newest first as GameBanana returns them.
  Future<List<GameBananaFile>> files(int modId) async {
    final json = await _get(Uri.parse('$base/Mod/$modId/DownloadPage'));
    final files = (json['_aFiles'] as List?) ?? const [];

    return files
        .cast<Map<String, dynamic>>()
        .map(GameBananaFile.fromJson)
        .toList();
  }

  List<GameBananaMod> _records(Map<String, dynamic> json) {
    final records = (json['_aRecords'] as List?) ?? const [];

    return records
        .cast<Map<String, dynamic>>()
        // Guides and WiPs share the feed with mods and have nothing to install.
        .where((record) => record['_sModelName'] == 'Mod')
        .map(GameBananaMod.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final res = await _client.get(
      uri,
      headers: const {'User-Agent': 'modlinq-marketplace'},
    );

    if (res.statusCode != 200) {
      throw http.ClientException('GameBanana returned ${res.statusCode}', uri);
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
