import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/models/game_type.dart';
import 'package:modlinq/utils/game_roster.dart';
import 'package:modlinq/utils/mod_categories.dart';
import 'package:modlinq/utils/nte_characters.dart';
import 'package:modlinq/utils/ww_characters.dart';
import 'package:modlinq/utils/zzz_characters.dart';

void main() {
  group('roster separation', () {
    test('each game gets its own character list', () {
      expect(GameRoster.of(GameType.zzz).characterIds, zzzCharacters);
      expect(GameRoster.of(GameType.wutheringWaves).characterIds, wwCharacters);
      expect(GameRoster.of(GameType.nte).characterIds, nteCharacters);
    });

    test('no game shows another game\'s exclusive characters', () {
      final zzz = GameRoster.of(GameType.zzz).characterIds.toSet();
      final ww = GameRoster.of(GameType.wutheringWaves).characterIds.toSet();
      final nte = GameRoster.of(GameType.nte).characterIds.toSet();

      expect(zzz, isNot(contains('mint')), reason: 'mint is an NTE Esper');
      expect(nte, isNot(contains('miyabi')), reason: 'miyabi is a ZZZ agent');
      expect(ww, isNot(contains('sigrid')), reason: 'sigrid is a ZZZ agent');
      expect(nte, isNot(contains('yinlin')), reason: 'yinlin is a WW resonator');
    });

    test('each game uses its own asset folder', () {
      expect(GameRoster.of(GameType.zzz).iconPathFor('anby'), 'assets/characters/anby.png');
      expect(
        GameRoster.of(GameType.wutheringWaves).iconPathFor('yinlin'),
        'assets/characters_ww/yinlin.png',
      );
      expect(GameRoster.of(GameType.nte).iconPathFor('mint'), 'assets/characters_nte/mint.png');
    });

    test('display names resolve through the right game', () {
      expect(GameRoster.of(GameType.zzz).displayNameOf('lycaon'), 'Von Lycaon');
      expect(GameRoster.of(GameType.nte).displayNameOf('zero'), 'Esper Zero');
    });

    test('every game can assign to misc and unknown', () {
      for (final game in GameType.values) {
        final assignable = GameRoster.of(game).assignableIds;
        expect(assignable, contains(ModCategories.misc));
        expect(assignable, contains(ModCategories.unknown));
        expect(assignable.length, GameRoster.of(game).characterIds.length + 2);
      }
    });

    test('bucket labels are used instead of character lookups', () {
      final roster = GameRoster.of(GameType.zzz);

      expect(
        roster.labelFor(ModCategories.misc, miscLabel: 'Misc', unknownLabel: 'Unknown'),
        'Misc',
      );
      expect(
        roster.labelFor(ModCategories.unknown, miscLabel: 'Misc', unknownLabel: 'Unknown'),
        'Unknown',
      );
      expect(
        roster.labelFor('anby', miscLabel: 'Misc', unknownLabel: 'Unknown'),
        'Anby',
      );
    });
  });
}
