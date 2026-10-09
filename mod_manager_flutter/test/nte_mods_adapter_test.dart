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

  final List<NteMod> mods;

  @override
  List<NteMod> listMods() => mods;

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

NteMod _mod(String name, {String? category}) =>
    NteMod(name: name, dirPath: '/nowhere/$name', files: const [], category: category);

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
