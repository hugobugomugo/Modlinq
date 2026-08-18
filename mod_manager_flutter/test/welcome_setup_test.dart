import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modlinq/l10n/app_localizations.dart';
import 'package:modlinq/models/game_type.dart';
import 'package:modlinq/screens/welcome_screen.dart';

/// Kept as a single test on purpose: the l10n delegate loads
/// assets/l10n/en.json off rootBundle, which is real async i/o. Splitting this
/// into several testWidgets resets the binding between them and the tree comes
/// up empty, so the whole setup flow is walked in one pass instead.
void main() {
  testWidgets('first run setup is per game and skippable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
          home: WelcomeScreen(onComplete: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // skippable straight away, without filling anything in
    final skip = find.text('Skip for now');
    expect(skip, findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
              find.ancestor(of: skip, matching: find.byType(TextButton)))
          .onPressed,
      isNotNull,
      reason: 'skip must work with every path left blank',
    );

    await tester.tap(find.text('Next'));
    await tester.pump(const Duration(seconds: 1));

    // one tab per game, not just zzz
    expect(find.byType(TabBar), findsOneWidget);
    for (final game in GameType.values) {
      expect(
        find.text(game.shortLabel),
        findsOneWidget,
        reason: '${game.displayName} needs its own setup tab',
      );
    }

    // fields say which game they belong to
    expect(find.textContaining('Zenless Zone Zero'), findsWidgets);

    await tester.tap(find.text(GameType.wutheringWaves.shortLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('Wuthering Waves'), findsWidgets);

    await tester.tap(find.text(GameType.nte.shortLabel));
    await tester.pumpAndSettle();
    expect(find.text('Game folder'), findsOneWidget);
    expect(find.text('Detect'), findsOneWidget);
  });
}
