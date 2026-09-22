import 'dart:convert';

import 'package:http/http.dart' as http;

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

  const GameBananaMod({
    required this.id,
    required this.name,
    required this.author,
    required this.profileUrl,
    required this.hasFiles,
    this.thumbnailUrl,
    this.category,
    this.updatedAt,
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
  static const int perPage = 20;

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
  Future<List<GameBananaMod>> search({
    required int gameId,
    required String query,
    int page = 1,
  }) async {
    final uri = Uri.parse(
      '$base/Util/Search/Results'
      '?_sModelName=Mod&_idGameRow=$gameId&_nPage=$page&_nPerpage=$perPage'
      '&_sSearchString=${Uri.encodeComponent(query)}',
    );

    return _records(await _get(uri));
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
