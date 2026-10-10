import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/models/game_type.dart';
import 'package:modlinq/models/nte_mod.dart';
import 'package:modlinq/services/nte_mod_library.dart';
import 'package:modlinq/services/nte_mods_adapter.dart';
import 'package:modlinq/utils/mod_categories.dart';

/// A library of names, which is all the grouping cares about.
class _FakeManager implements FileModManager {
  _FakeManager(this.gameType, this.mods);

  @override
  final GameType gameType;

  List<NteMod> mods;

  /// Every setEnabled, in order, as `name=true|false`.
  final List<String> calls = [];

  @override
  List<NteMod> listMods() => mods;

  @override
  Future<NteApplyResult> setEnabled(String modName, bool enabled) async {
    calls.add('$modName=$enabled');
    mods = [
      for (final mod in mods)
        mod.name == modName ? mod.copyWith(enabled: enabled) : mod,
    ];

    return NteApplyResult(applied: [modName]);
  }

  @override
  NteModLibrary get library => NteModLibrary('/nowhere');

  @override
  String? previewImageFor(String modName) => null;

  @override
  bool isFavorite(String modName) => false;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not part of grouping');
}

/// Reports the hero's old skin as locked by the game, the way a running
/// Deadlock does.
class _FailingManager extends _FakeManager {
  _FailingManager(super.gameType, super.mods);

  @override
  Future<NteApplyResult> setEnabled(String modName, bool enabled) async {
    if (!enabled) return NteApplyResult(locked: [modName]);
    return super.setEnabled(modName, enabled);
  }
}

NteMod _mod(String name, {String? category, bool enabled = false}) => NteMod(
  name: name,
  dirPath: '/nowhere/$name',
  files: const [],
  category: category,
  enabled: enabled,
);

void main() {
  NteModsAdapter adapterFor(GameType game, List<NteMod> mods) =>
      NteModsAdapter(_FakeManager(game, mods));

  group('deadlock grouping', () {
    test('mods land under the hero their folder name names', () {
      final adapter = adapterFor(GameType.deadlock, [
        _mod('baronessmina'),
        _mod('orange_mina_80c18'),
        _mod('roxy_over_graves'),
        _mod('pak01_dir_59447'),
      ]);

      final categories = adapter.buildCategories(adapter.listMods());

      expect(categories.map((c) => c.id), ['graves', 'mina']);
      expect(
        categories.firstWhere((c) => c.id == 'mina').skins.map((m) => m.id),
        ['baronessmina', 'orange_mina_80c18'],
      );
    });

    test('groups carry the hero name and portrait, not the raw id', () {
      final adapter = adapterFor(GameType.deadlock, [
        _mod('grey_talon_arrows'),
        _mod('mo_krill_retexture'),
      ]);

      final categories = adapter.buildCategories(adapter.listMods());

      expect(categories.map((c) => c.name), ['Grey Talon', 'Mo & Krill']);
      expect(
        categories.first.iconPath,
        'assets/characters_deadlock/grey_talon.png',
      );
    });

    test('a mod nobody can place stays out of the hero categories', () {
      final adapter = adapterFor(GameType.deadlock, [_mod('gothamchess')]);
      final mods = adapter.listMods();

      expect(mods.single.characterId, ModCategories.unknown);
      expect(adapter.buildCategories(mods), isEmpty);
      expect(adapter.specialBuckets(mods).keys, [ModCategories.unknown]);
    });

    test('an assigned category beats what the name suggests', () {
      // Dragging a mod onto a hero has to stick even when its name says
      // otherwise, which is the whole point of the assignment.
      final adapter = adapterFor(GameType.deadlock, [
        _mod('baronessmina', category: 'paige'),
      ]);

      final categories = adapter.buildCategories(adapter.listMods());

      expect(categories.single.id, 'paige');
      expect(categories.single.name, 'Paige');
    });
  });

  group('single mode', () {
    // A hero wears one skin at a time. Pak games ignored this rule entirely:
    // two Graves skins could be enabled at once while the toggle said single.
    test('enabling a skin turns the hero\'s other skins off', () async {
      final manager = _FakeManager(GameType.deadlock, [
        _mod('graves_one', enabled: true),
        _mod('graves_two'),
      ]);
      final adapter = NteModsAdapter(manager);
      final two = adapter.listMods().firstWhere((m) => m.id == 'graves_two');

      await adapter.toggle(two, exclusive: true);

      expect(manager.calls, ['graves_one=false', 'graves_two=true']);
    });

    test('another hero keeps whatever it had on', () async {
      final manager = _FakeManager(GameType.deadlock, [
        _mod('mina_skin', enabled: true),
        _mod('graves_one', enabled: true),
        _mod('graves_two'),
      ]);
      final adapter = NteModsAdapter(manager);
      final two = adapter.listMods().firstWhere((m) => m.id == 'graves_two');

      await adapter.toggle(two, exclusive: true);

      expect(manager.calls, ['graves_one=false', 'graves_two=true']);
    });

    test('multi mode leaves the others alone', () async {
      final manager = _FakeManager(GameType.deadlock, [
        _mod('graves_one', enabled: true),
        _mod('graves_two'),
      ]);
      final adapter = NteModsAdapter(manager);
      final two = adapter.listMods().firstWhere((m) => m.id == 'graves_two');

      await adapter.toggle(two);

      expect(manager.calls, ['graves_two=true']);
    });

    test('switching a skin off never switches another on', () async {
      final manager = _FakeManager(GameType.deadlock, [
        _mod('graves_one', enabled: true),
        _mod('graves_two', enabled: true),
      ]);
      final adapter = NteModsAdapter(manager);
      final one = adapter.listMods().firstWhere((m) => m.id == 'graves_one');

      await adapter.toggle(one, exclusive: true);

      expect(manager.calls, ['graves_one=false']);
    });

    test('the shared buckets stay multi, whatever the mode says', () async {
      // HUD, audio and map mods share the unknown bucket without having
      // anything to do with each other.
      final manager = _FakeManager(GameType.deadlock, [
        _mod('updatedsounds', enabled: true),
        _mod('v5_top_bar_plus'),
      ]);
      final adapter = NteModsAdapter(manager);
      final bar = adapter.listMods().firstWhere((m) => m.id == 'v5_top_bar_plus');

      await adapter.toggle(bar, exclusive: true);

      expect(manager.calls, ['v5_top_bar_plus=true']);
    });

    test('a failure from any step is reported back', () async {
      final manager = _FailingManager(GameType.deadlock, [
        _mod('graves_one', enabled: true),
        _mod('graves_two'),
      ]);
      final adapter = NteModsAdapter(manager);
      final two = adapter.listMods().firstWhere((m) => m.id == 'graves_two');

      final result = await adapter.toggle(two, exclusive: true);

      expect(result.locked, ['graves_one']);
      expect(result.applied, ['graves_two']);
    });
  });

  group('nte grouping', () {
    test('a free-form category keeps its own name', () {
      final adapter = adapterFor(GameType.nte, [
        _mod('some_mod', category: 'My Stuff'),
      ]);

      final categories = adapter.buildCategories(adapter.listMods());

      expect(categories.single.id, 'My Stuff');
      expect(categories.single.name, 'My Stuff');
    });

    test('espers still resolve through the NTE roster', () {
      final adapter = adapterFor(GameType.nte, [_mod('adler_outfit')]);

      final categories = adapter.buildCategories(adapter.listMods());

      expect(categories.single.id, 'adler');
      expect(categories.single.iconPath, 'assets/characters_nte/adler.png');
    });
  });
}
