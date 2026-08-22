import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/models/game_type.dart';
import 'package:modlinq/utils/game_roster.dart';

void main() {
  // Cards fall back to a grey person icon when the file is missing, which is
  // easy to miss until the game is opened. These keep the rosters honest.
  //
  // Skips mean artwork that does not exist in the repo yet, not a rule that
  // does not apply. Drop the entry once the files land.
  const missingArtwork = {
    GameType.zzz: 'no artwork yet for the 3.1 additions sigrid and '
        'starlightbilly',
    GameType.wutheringWaves: 'assets/characters_ww is empty, no portraits yet',
  };

  for (final game in GameType.values) {
    final roster = GameRoster.of(game);

    group('${game.name} portraits', () {
      test('every character in the roster has an icon on disk',
          skip: missingArtwork[game], () {
        final missing = roster.characterIds
            .where((id) => !File(roster.iconPathFor(id)).existsSync())
            .toList();

        expect(missing, isEmpty, reason: 'no portrait for: $missing');
      });

      test('every icon on disk belongs to a character in the roster', () {
        final folder = Directory(roster.assetFolder);
        if (!folder.existsSync()) return;

        final known = roster.characterIds.toSet();
        final orphans = folder
            .listSync()
            .whereType<File>()
            .where((f) => p.extension(f.path).toLowerCase() == '.png')
            .map((f) => p.basenameWithoutExtension(f.path))
            .where((name) => !known.contains(name))
            .toList();

        expect(orphans, isEmpty, reason: 'portrait without a character: $orphans');
      });
    });
  }
}
