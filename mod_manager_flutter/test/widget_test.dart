// Roster integrity tests — guard character list updates on game patches.

import 'package:flutter_test/flutter_test.dart';

import 'package:mod_manager_flutter/utils/zzz_characters.dart';

void main() {
  group('ZZZ roster integrity', () {
    test('ids are unique', () {
      final ids = zzzCharactersData.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('display names and asset names are non-empty', () {
      for (final c in zzzCharactersData) {
        expect(c.displayName.trim(), isNotEmpty, reason: 'id=${c.id}');
        expect(c.assetName.trim(), isNotEmpty, reason: 'id=${c.id}');
      }
    });

    test('legacy list stays in sync with data list', () {
      final dataIds = zzzCharactersData.map((c) => c.id).toSet();
      expect(zzzCharacters.toSet(), dataIds);
    });

    test('3.1 patch characters present', () {
      final ids = zzzCharactersData.map((c) => c.id).toSet();
      expect(ids, containsAll(['sigrid', 'starlightbilly', 'remielle']));
    });

    test('lookup helpers resolve known and unknown ids', () {
      expect(getCharacterDisplayName('sigrid'), 'Sigrid');
      expect(getCharacterDisplayName('starlightbilly'), 'Starlight Billy');
      expect(getCharacterDisplayName('does_not_exist'), 'does_not_exist');
      expect(getCharacterAssetName('sigrid'), 'sigrid');
    });
  });
}
