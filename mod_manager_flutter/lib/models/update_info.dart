class UpdateInfo {
  final String version;
  final String tag;
  final String notes;
  final String assetName;
  final String assetUrl;
  final int assetSize;
  final String? checksumUrl;

  const UpdateInfo({
    required this.version,
    required this.tag,
    required this.notes,
    required this.assetName,
    required this.assetUrl,
    required this.assetSize,
    this.checksumUrl,
  });
}
