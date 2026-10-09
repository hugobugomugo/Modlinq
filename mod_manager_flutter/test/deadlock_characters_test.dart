import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/utils/deadlock_characters.dart';

void main() {
  group('roster', () {
    test('carries every hero GameBanana files skins under', () {
      expect(deadlockCharacters.length, deadlockCharactersData.length);
      expect(deadlockCharacters, contains('mina'));
      expect(deadlockCharacters, contains('grey_talon'));
      expect(deadlockCharacters, contains('mo_krill'));
    });

    test('ids are slugs, display names stay readable', () {
      expect(getDeadlockCharacterDisplayName('mo_krill'), 'Mo & Krill');
      expect(getDeadlockCharacterDisplayName('grey_talon'), 'Grey Talon');
      expect(getDeadlockCharacterDisplayName('ratking'), 'RatKing');
    });

    test('an unknown id falls back to itself rather than throwing', () {
      expect(getDeadlockCharacterDisplayName('nobody'), 'nobody');
    });
  });

  group('detect', () {
    test('finds the hero in a mod name', () {
      expect(detectDeadlockCharacter('Bottom Heavy Mina Ha'), 'mina');
      expect(detectDeadlockCharacter('Toon Ivy (SOUL ORB FIX)'), 'ivy');
      expect(detectDeadlockCharacter('Lashlyn Lash Skin'), 'lash');
    });

    test('matches two-word heroes whole or by surname', () {
      expect(detectDeadlockCharacter('Grey Talon rework'), 'grey_talon');
      expect(detectDeadlockCharacter('Talon arrows'), 'grey_talon');
      expect(detectDeadlockCharacter('Mo & Krill retexture'), 'mo_krill');
    });

    test('a word that merely starts with a hero name is not a match', () {
      // "Rem" is a hero, so a substring match would claim every remodel,
      // remaster and remix in the catalogue.
      expect(detectDeadlockCharacter('Yamato remodel'), 'yamato');
      expect(detectDeadlockCharacter('HUD remaster'), isNull);
      expect(detectDeadlockCharacter('Rem & Relaxation Skin'), 'rem');
    });

    test('the earliest hero wins when several appear', () {
      expect(detectDeadlockCharacter('Ivy wings for Mina'), 'ivy');
    });

    test('nothing matched returns null, never a guess', () {
      expect(detectDeadlockCharacter('DEADLOCK TOASTED'), isNull);
      expect(detectDeadlockCharacter('QOL Lock'), isNull);
    });

    test('finds a hero glued into a word', () {
      // Real folder names from a Deadlock library. Whole-word matching filed
      // all of these under unknown.
      expect(detectDeadlockCharacter('baronessmina'), 'mina');
      expect(detectDeadlockCharacter('minaheels'), 'mina');
      expect(detectDeadlockCharacter('bunnypaige_black'), 'paige');
      expect(detectDeadlockCharacter('paigecowprintaddon'), 'paige');
      expect(detectDeadlockCharacter('dawnkitzusilver_40e56'), 'silver');
      expect(detectDeadlockCharacter('variationgeistcombined'), 'lady_geist');
      expect(detectDeadlockCharacter('bikinidicta_v2_082'), 'vindicta');
    });

    test('a short alias stays glued-proof', () {
      // Four letters have to sit at a word edge and three have to be the whole
      // word, or half the catalogue lands on the wrong hero.
      expect(detectDeadlockCharacter('sparxie_main'), isNull);
      expect(detectDeadlockCharacter('flashlight rework'), isNull);
      expect(detectDeadlockCharacter('ivory tower'), isNull);
      expect(detectDeadlockCharacter('compressed remix'), isNull);
    });
  });
}
