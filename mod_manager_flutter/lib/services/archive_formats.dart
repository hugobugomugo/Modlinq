import 'package:path/path.dart' as p;

/// The archive formats the mod importer understands.
///
/// Split by what unpacking them costs the user: [native] formats are handled
/// by the bundled `archive` package, while [externalTool] formats only work
/// when a 7-Zip binary is installed on the system.
class ArchiveFormats {
  /// Formats unpacked without any external dependency.
  ///
  /// Kept deliberately in sync with what `extractFileToDisk` accepts. Listing
  /// a format it does not know makes extraction throw an `ArgumentError`
  /// instead of failing gracefully.
  static const List<String> native = [
    'zip',
    'tar',
    'tar.gz',
    'tgz',
    'tar.bz2',
    'tbz',
    'tar.xz',
    'txz',
  ];

  /// Formats that require a 7-Zip binary on the system.
  static const List<String> externalTool = ['rar', '7z'];

  /// Compressed tarballs whose extension spans two components.
  static const List<String> _compoundExtensions = [
    'tar.gz',
    'tar.bz2',
    'tar.xz',
  ];

  /// The extension of [filePath], lowercase and without the leading dot.
  ///
  /// Returns both components for compressed tarballs, so `mod.tar.gz` reads as
  /// `tar.gz` rather than `gz`. Empty when the file name carries no extension.
  static String extensionOf(String filePath) {
    final name = p.basename(filePath).toLowerCase();

    for (final extension in _compoundExtensions) {
      if (name.endsWith('.$extension')) return extension;
    }

    final extension = p.extension(name);
    return extension.isEmpty ? '' : extension.substring(1);
  }

  /// The file name of [filePath] with its archive extension removed.
  ///
  /// Strips both components of a compressed tarball, so a mod imported from
  /// `CoolSkin.tar.gz` is named `CoolSkin` and not `CoolSkin.tar`. Casing of
  /// the name is preserved because it ends up in the UI.
  static String baseNameOf(String filePath) {
    final name = p.basename(filePath);
    final extension = extensionOf(filePath);

    if (extension.isEmpty) return name;
    return name.substring(0, name.length - extension.length - 1);
  }

  /// Whether [filePath] unpacks without an external tool.
  static bool isNative(String filePath) =>
      native.contains(extensionOf(filePath));

  /// Whether [filePath] needs a 7-Zip binary to unpack.
  static bool needsExternalTool(String filePath) =>
      externalTool.contains(extensionOf(filePath));

  /// Whether [filePath] is an archive the importer can handle at all.
  static bool isSupported(String filePath) =>
      isNative(filePath) || needsExternalTool(filePath);

  /// Extensions to offer in a file picker.
  ///
  /// [includeExternalTool] should reflect whether a 7-Zip binary was actually
  /// found, so the picker never advertises a format the machine cannot open.
  static List<String> pickerExtensions({required bool includeExternalTool}) => [
    ...native,
    if (includeExternalTool) ...externalTool,
  ];
}
