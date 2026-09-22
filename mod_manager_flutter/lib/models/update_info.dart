class UpdateInfo {
  final String version;
  final String tag;
  final String notes;
  final String assetName;
  final String assetUrl;
  final int assetSize;
  final String? checksumUrl;

  /// Windows installer asset, when the release ships one. Only an installed
  /// copy uses it; portable copies always swap the zip.
  final String? installerName;
  final String? installerUrl;

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
    this.checksumUrl,
    this.installerName,
    this.installerUrl,
  });
}
