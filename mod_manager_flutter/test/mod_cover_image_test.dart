import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/screens/components/mod_cover_image.dart';

void main() {
  // A cover that decodes at source size and samples with the default
  // FilterQuality.low is what made the grid look pixelated, and neither is
  // visible in a golden-free widget test unless it is asserted directly.
  Future<Image> pumpCover(
    WidgetTester tester, {
    required Size size,
    double devicePixelRatio = 2,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(devicePixelRatio: devicePixelRatio),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: ModCoverImage.file(File('cover.png')),
            ),
          ),
        ),
      ),
    );

    return tester.widget<Image>(find.byType(Image));
  }

  testWidgets('decodes at the card size in device pixels', (tester) async {
    final image = await pumpCover(tester, size: const Size(220, 124));

    final resized = image.image as ResizeImage;
    expect(resized.width, 440);
    expect(resized.height, isNull);
    expect(resized.allowUpscaling, isFalse);
  });

  testWidgets('a cover smaller than the card is never upscaled on decode', (
    tester,
  ) async {
    final image = await pumpCover(tester, size: const Size(220, 124));

    // Blowing a 100px thumbnail up to card size in the decoder would cost
    // memory and add no detail; the mipmapped sampler handles that case.
    expect((image.image as ResizeImage).allowUpscaling, isFalse);
  });

  testWidgets('samples with mipmaps rather than the default low quality', (
    tester,
  ) async {
    final image = await pumpCover(tester, size: const Size(220, 124));

    expect(image.filterQuality, FilterQuality.medium);
    expect(image.fit, BoxFit.cover);
  });

  testWidgets('an unbounded width leaves the full image to the painter', (
    tester,
  ) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            children: [ModCoverImage.file(File('cover.png'))],
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<FileImage>());
  });
}
