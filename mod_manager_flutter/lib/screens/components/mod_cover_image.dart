import 'dart:io';

import 'package:flutter/material.dart';

/// A mod's cover art, decoded at the size the card actually draws it.
///
/// Covers used to go through a plain `Image.file` with no cache size and the
/// default [FilterQuality.low]. That decodes a 1600px GameBanana preview at
/// full size and then throws away pixels with a single bilinear tap, which is
/// what made covers look pixelated and noisy; small previews that get blown up
/// to card size looked blocky for the same reason.
///
/// Decoding to the card's own pixel size and sampling with [FilterQuality
/// .medium] (bilinear plus mipmaps) fixes both ends and cuts the memory a grid
/// of covers holds, since each bitmap is kept at display size instead of
/// source size.
class ModCoverImage extends StatelessWidget {
  const ModCoverImage({
    super.key,
    required this.image,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  /// Cover on disk, the common case: an installed mod's preview image.
  ModCoverImage.file(
    File file, {
    super.key,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  }) : image = FileImage(file);

  /// Cover served by GameBanana, used while browsing the marketplace.
  ModCoverImage.network(
    String url, {
    super.key,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  }) : image = NetworkImage(url);

  final ImageProvider image;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = MediaQuery.devicePixelRatioOf(context);

        // Width drives the decode: covers and cards are both landscape, so the
        // height that falls out of it is at least the card's. An unbounded
        // width means no target to decode to, and the full image is used.
        final target = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? (constraints.maxWidth * ratio).round()
            : null;

        return Image(
          image: target == null
              ? image
              : ResizeImage(image, width: target, allowUpscaling: false),
          fit: fit,
          filterQuality: FilterQuality.medium,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}
