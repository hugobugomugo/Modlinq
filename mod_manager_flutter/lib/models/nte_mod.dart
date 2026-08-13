import 'package:path/path.dart' as p;

/// A mod stored in the app-managed NTE library.
///
/// The library folder is the source of truth: each mod is one directory whose
/// name is its id. Enabling a mod copies its files into the game; the library
/// copy is never moved, so disabling can never lose data.
class NteMod {
  /// Folder name inside the library. Unique, and used as the id.
  final String name;

  /// Absolute path of the mod's folder in the library.
  final String dirPath;

  /// Absolute paths of the mod's payload files, excluding helper files such as
  /// `mod.json`, `icon.png` and preview images.
  final List<String> files;

  /// User-defined group. `null` means the mod sits at the root of `~mods`.
  final String? category;

  /// Whether the mod's files are currently present in the game folder.
  final bool enabled;

  const NteMod({
    required this.name,
    required this.dirPath,
    required this.files,
    this.category,
    this.enabled = false,
  });

  /// Unreal `.pak` / `.ucas` / `.utoc` content, installed into `~mods`.
  bool get isPak => files.any((f) => _extension(f) == 'pak');

  /// Native `.asi` plugins, installed next to the game binary.
  bool get isAsi => files.any((f) => _extension(f) == 'asi');

  /// A mod with no recognised payload cannot be installed anywhere.
  bool get isInstallable => isPak || isAsi;

  /// Paths relative to [dirPath], preserving any nested folder layout.
  List<String> get relativeFiles =>
      files.map((f) => p.relative(f, from: dirPath)).toList();

  NteMod copyWith({String? category, bool? enabled}) => NteMod(
    name: name,
    dirPath: dirPath,
    files: files,
    category: category ?? this.category,
    enabled: enabled ?? this.enabled,
  );

  static String _extension(String path) =>
      p.extension(path).replaceFirst('.', '').toLowerCase();
}

/// Outcome of enabling or disabling mods.
class NteApplyResult {
  /// Mods whose files are now in the requested state.
  final List<String> applied;

  /// Mods that could not be changed because the game holds their files open.
  /// These are retried automatically on the next apply.
  final List<String> locked;

  /// Failures that are not lock-related, keyed by mod name.
  final Map<String, String> errors;

  const NteApplyResult({
    this.applied = const [],
    this.locked = const [],
    this.errors = const {},
  });

  bool get hasFailures => locked.isNotEmpty || errors.isNotEmpty;
}
