/// Turns a marketplace title into a name the library can use as a folder.
///
/// A mod's name *is* its folder name, and config keys (category, favorite,
/// pak slot) are stored under it, so the name has to survive both Windows'
/// and Linux' rules without needing a separate display-name table.
class ModName {
  ModName._();

  /// Windows forbids these outright; Linux only forbids `/`, but a library
  /// copied between the two should keep working.
  static final RegExp _illegal = RegExp(r'[<>:"/\\|?*\x00-\x1F]');

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Device names Windows still refuses, with or without an extension.
  static const Set<String> _reserved = {
    'con',
    'prn',
    'aux',
    'nul',
    'com1',
    'com2',
    'com3',
    'com4',
    'com5',
    'com6',
    'com7',
    'com8',
    'com9',
    'lpt1',
    'lpt2',
    'lpt3',
    'lpt4',
    'lpt5',
    'lpt6',
    'lpt7',
    'lpt8',
    'lpt9',
  };

  /// Keeps the full path well under Windows' 260 characters once the library
  /// root and the mod's own files are added.
  static const int maxLength = 80;

  /// The folder name for [title], or null when nothing usable is left and the
  /// caller should fall back to the archive's own name.
  static String? sanitize(String title) {
    var name = title
        .replaceAll(_illegal, ' ')
        .replaceAll(_whitespace, ' ')
        .trim();

    if (name.length > maxLength) {
      name = name.substring(0, maxLength).trim();
    }

    // Windows drops trailing dots and spaces silently, which would make the
    // folder the app creates and the folder it looks for differ.
    name = name.replaceAll(RegExp(r'[. ]+$'), '');

    if (name.isEmpty) return null;
    if (_reserved.contains(name.toLowerCase())) return '$name mod';

    return name;
  }

  /// [name], or the first `name (n)` variant that is not in [taken].
  ///
  /// Comparison is case-insensitive because Windows and macOS treat
  /// "Yamato" and "yamato" as the same folder.
  static String unique(String name, Set<String> taken) {
    final lower = taken.map((e) => e.toLowerCase()).toSet();
    if (!lower.contains(name.toLowerCase())) return name;

    for (var n = 2; n < 1000; n++) {
      final candidate = '$name ($n)';
      if (!lower.contains(candidate.toLowerCase())) return candidate;
    }

    return '$name (${DateTime.now().millisecondsSinceEpoch})';
  }
}
