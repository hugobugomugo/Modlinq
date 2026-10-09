import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/utils/mod_name.dart';

void main() {
  group('sanitize', () {
    test('keeps an ordinary marketplace title as it is', () {
      expect(ModName.sanitize('Yamato redesign'), 'Yamato redesign');
    });

    test('drops characters Windows refuses in a folder name', () {
      // Real GameBanana titles carry these: "true ru patriot | flag + anthem".
      expect(
        ModName.sanitize('true ru patriot | flag + anthem'),
        'true ru patriot flag + anthem',
      );
      expect(ModName.sanitize(r'a/b\c:d*e?f"g<h>i'), 'a b c d e f g h i');
    });

    test('strips the trailing dots and spaces Windows silently eats', () {
      expect(ModName.sanitize('Toon Ivy...  '), 'Toon Ivy');
    });

    test('caps the length so the full path stays usable', () {
      final name = ModName.sanitize('x' * 200);

      expect(name, isNotNull);
      expect(name!.length, ModName.maxLength);
    });

    test('a title that is only illegal characters falls back to null', () {
      expect(ModName.sanitize('///'), isNull);
      expect(ModName.sanitize('   '), isNull);
    });

    test('a reserved device name is made harmless', () {
      expect(ModName.sanitize('CON'), 'CON mod');
      expect(ModName.sanitize('com1'), 'com1 mod');
    });
  });

  group('unique', () {
    test('an unused name is returned untouched', () {
      expect(ModName.unique('Holliday', {'Toon Ivy'}), 'Holliday');
    });

    test('a taken name gets the first free number', () {
      expect(
        ModName.unique('Holliday', {'Holliday', 'Holliday (2)'}),
        'Holliday (3)',
      );
    });

    test('collision is case-insensitive, like Windows and macOS', () {
      expect(ModName.unique('Holliday', {'holliday'}), 'Holliday (2)');
    });
  });
}
