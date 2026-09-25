// Guards the Riverpod lifecycle of the marketplace screen.
//
// `ref` is unusable once a widget is unmounted, so reading a provider from
// dispose() throws and silently skips every teardown line after it: the
// scroll controller, the search controller and super.dispose() all leak.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/screens/marketplace_screen.dart';

void main() {
  testWidgets('disposing the marketplace screen never reads a provider', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: MarketplaceScreen())),
      ),
    );

    // Unmount it the way switching away from the marketplace tab does.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
