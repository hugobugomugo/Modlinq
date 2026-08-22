import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/services/archive_formats.dart';

void main() {
  group('extensionOf', () {
    test('keeps both components of a compressed tarball', () {
      expect(ArchiveFormats.extensionOf('Skin.tar.gz'), 'tar.gz');
      expect(ArchiveFormats.extensionOf('Skin.tar.bz2'), 'tar.bz2');
      expect(ArchiveFormats.extensionOf('Skin.tar.xz'), 'tar.xz');
    });

    test('returns the single component for other archives', () {
      expect(ArchiveFormats.extensionOf('Skin.zip'), 'zip');
      expect(ArchiveFormats.extensionOf('Skin.tgz'), 'tgz');
      expect(ArchiveFormats.extensionOf('Skin.tar'), 'tar');
    });

    test('does not read a bare .gz as a tarball', () {
      expect(ArchiveFormats.extensionOf('Skin.gz'), 'gz');
    });

    test('lowercases the extension', () {
      expect(ArchiveFormats.extensionOf('SKIN.ZIP'), 'zip');
      expect(ArchiveFormats.extensionOf('SKIN.TAR.GZ'), 'tar.gz');
    });

    test('ignores dots in parent directories', () {
      expect(ArchiveFormats.extensionOf('/home/my.mods/Skin.zip'), 'zip');
      expect(ArchiveFormats.extensionOf('/home/my.tar.gz/Skin'), '');
    });

    test('returns empty for a file without an extension', () {
      expect(ArchiveFormats.extensionOf('Skin'), '');
    });
  });

  group('baseNameOf', () {
    test('strips both components of a compressed tarball', () {
      expect(ArchiveFormats.baseNameOf('/mods/CoolSkin.tar.gz'), 'CoolSkin');
      expect(ArchiveFormats.baseNameOf('CoolSkin.tar.bz2'), 'CoolSkin');
    });

    test('strips a single-component extension', () {
      expect(ArchiveFormats.baseNameOf('/mods/CoolSkin.zip'), 'CoolSkin');
    });

    test('keeps the original casing', () {
      expect(ArchiveFormats.baseNameOf('CoolSkin.TAR.GZ'), 'CoolSkin');
    });

    test('returns the whole name when there is no extension', () {
      expect(ArchiveFormats.baseNameOf('/mods/CoolSkin'), 'CoolSkin');
    });
  });

  group('classification', () {
    test('unpacks native formats without an external tool', () {
      for (final name in [
        'a.zip',
        'a.tar',
        'a.tar.gz',
        'a.tgz',
        'a.tar.bz2',
        'a.tbz',
        'a.tar.xz',
        'a.txz',
      ]) {
        expect(ArchiveFormats.isNative(name), isTrue, reason: name);
        expect(ArchiveFormats.needsExternalTool(name), isFalse, reason: name);
      }
    });

    test('routes rar and 7z through an external tool', () {
      for (final name in ['a.rar', 'a.7z']) {
        expect(ArchiveFormats.needsExternalTool(name), isTrue, reason: name);
        expect(ArchiveFormats.isNative(name), isFalse, reason: name);
      }
    });

    test('rejects files that are not archives', () {
      for (final name in ['a.pak', 'a.asi', 'a.gz', 'a.png', 'a']) {
        expect(ArchiveFormats.isSupported(name), isFalse, reason: name);
      }
    });

    test('treats both native and external formats as supported', () {
      expect(ArchiveFormats.isSupported('a.tar.xz'), isTrue);
      expect(ArchiveFormats.isSupported('a.rar'), isTrue);
    });
  });

  group('pickerExtensions', () {
    test('offers only native formats when no external tool is available', () {
      final extensions = ArchiveFormats.pickerExtensions(
        includeExternalTool: false,
      );

      expect(extensions, contains('zip'));
      expect(extensions, contains('tar.gz'));
      expect(extensions, isNot(contains('rar')));
      expect(extensions, isNot(contains('7z')));
    });

    test('adds rar and 7z when an external tool is available', () {
      final extensions = ArchiveFormats.pickerExtensions(
        includeExternalTool: true,
      );

      expect(extensions, containsAll(['zip', 'tar.gz', 'rar', '7z']));
    });
  });
}
