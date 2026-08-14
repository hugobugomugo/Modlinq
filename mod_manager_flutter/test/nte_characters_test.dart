import 'package:flutter_test/flutter_test.dart';

import 'package:mod_manager_flutter/utils/mod_categories.dart';
import 'package:mod_manager_flutter/utils/nte_characters.dart';

void main() {
  group('detectNteCharacter', () {
    test('matches a plain character name', () {
      expect(detectNteCharacter('mint_nurse'), 'mint');
      expect(detectNteCharacter('nanally_cute_clothes_bear_edition_'), 'nanally');
      expect(detectNteCharacter('jiuyuan_maid_p'), 'jiuyuan');
    });

    test('matches a name embedded in a longer prefix', () {
      expect(detectNteCharacter('gothycatmint_black_hair_daa0e'), 'mint');
      expect(detectNteCharacter('lacrimosa_nanallynightyoutfit_97ded'), 'lacrimosa');
    });

    test('handles the double-l spelling used by mod authors', () {
      expect(detectNteCharacter('daffodill_fashion1_v1_p'), 'daffodil');
    });

    test('handles a misspelled character name', () {
      expect(detectNteCharacter('jiuyanbond'), 'jiuyuan');
    });

    test('is case and separator insensitive', () {
      expect(detectNteCharacter('Chiz--Elf__BASE'), 'chiz');
      expect(detectNteCharacter('MINT-Overalls'), 'mint');
    });

    test('returns null when nothing matches', () {
      expect(detectNteCharacter('fzero_porsche_buffed_v2_p'), isNull);
      expect(detectNteCharacter('anime_pomni'), isNull);
      expect(detectNteCharacter('__30'), isNull);
    });

    test('every alias target is a real character', () {
      for (final id in nteCharacterAliases.keys) {
        expect(nteCharacters, contains(id), reason: 'alias target $id');
      }
    });

    test('roster ids are unique and match the data list', () {
      expect(nteCharacters.toSet().length, nteCharacters.length);
      expect(nteCharactersData.map((c) => c.id).toSet(), nteCharacters.toSet());
    });
  });

  group('ModCategories', () {
    test('misc and unknown are recognised as special', () {
      expect(ModCategories.isSpecial(ModCategories.misc), isTrue);
      expect(ModCategories.isSpecial(ModCategories.unknown), isTrue);
    });

    test('a character id is not special', () {
      expect(ModCategories.isSpecial('mint'), isFalse);
    });
  });
}
