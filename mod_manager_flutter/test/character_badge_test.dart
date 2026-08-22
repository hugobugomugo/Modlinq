import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/utils/mod_categories.dart';

void main() {
  group('badgeIdFor', () {
    test('prefers the tag the user assigned by hand', () {
      expect(
        ModCategories.badgeIdFor(assignedTag: 'ellen', characterId: 'anby'),
        'ellen',
      );
    });

    test('falls back to the detected character when nothing was assigned', () {
      // How NTE works: grouping is detected from the folder name, never stored
      // in the tag map the other games use.
      expect(
        ModCategories.badgeIdFor(assignedTag: null, characterId: 'mint'),
        'mint',
      );
      expect(
        ModCategories.badgeIdFor(assignedTag: '', characterId: 'mint'),
        'mint',
      );
    });

    test('stays silent for the catch-all buckets', () {
      expect(
        ModCategories.badgeIdFor(
          assignedTag: null,
          characterId: ModCategories.unknown,
        ),
        isNull,
      );
      expect(
        ModCategories.badgeIdFor(
          assignedTag: ModCategories.misc,
          characterId: 'mint',
        ),
        isNull,
      );
    });

    test('stays silent when there is no character at all', () {
      expect(
        ModCategories.badgeIdFor(assignedTag: null, characterId: ''),
        isNull,
      );
    });
  });
}
