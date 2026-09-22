import 'dart:io';

import 'package:path/path.dart' as p;

/// Remembers which numbered slot a mod occupies.
///
/// The number is not derivable from the game folder: installing renames the
/// files to `pakNN_*.vpk`, so the original mod name is gone once it is in.
abstract class DeadlockSlotStore {
  Map<String, int> get slots;

  Future<void> save(Map<String, int> value);
}

/// In-memory store, used by tests and as a fallback before config is loaded.
class MemorySlotStore implements DeadlockSlotStore {
  Map<String, int> _slots = {};

  @override
  Map<String, int> get slots => Map.unmodifiable(_slots);

  @override
  Future<void> save(Map<String, int> value) async => _slots = Map.of(value);
}

/// Installs Deadlock mods into `game/citadel/addons`.
///
/// Source 2 only picks up archives named `pakNN_dir.vpk` with `NN` between 01
/// and 99, and it resolves conflicts by number: the lower one wins. So a mod
/// is not just copied, it is assigned a slot, and that slot is its load order.
class DeadlockModInstaller {
  final String gameRoot;
  final DeadlockSlotStore slots;

  DeadlockModInstaller({required this.gameRoot, required this.slots});

  static const int maxSlot = 99;

  String get addonsDir => p.join(gameRoot, 'game', 'citadel', 'addons');

  int? slotOf(String modName) => slots.slots[modName];

  /// Whether every file of [modName]'s slot is present in the game folder.
  bool isEnabled(String modName) {
    final slot = slotOf(modName);
    if (slot == null) return false;

    return File(p.join(addonsDir, '${_prefix(slot)}_dir.vpk')).existsSync();
  }

  /// Copies [modDir]'s archives into the game under the next free slot.
  Future<int> enable(String modName, String modDir) async {
    final existing = slotOf(modName);
    final slot = existing ?? _nextFreeSlot();

    await _installInto(slot, modName, modDir);
    return slot;
  }

  /// Moves [modName] to [slot], swapping with whoever sits there.
  ///
  /// Load order is the only thing a slot number means, so changing it is how
  /// the user resolves a conflict between two mods.
  Future<void> setSlot(String modName, int slot) async {
    if (slot < 1 || slot > maxSlot) {
      throw StateError('Slot must be between 1 and $maxSlot');
    }

    final current = slotOf(modName);
    if (current == slot) return;

    final occupant = slots.slots.entries
        .where((e) => e.value == slot && e.key != modName)
        .map((e) => e.key)
        .firstOrNull;

    if (current == null) {
      throw StateError('Mod "$modName" is not installed');
    }

    // Park the occupant first: renaming straight into an taken slot would
    // overwrite its files, and a half-done swap leaves the game unloadable.
    if (occupant != null) _movePrefix(_prefix(slot), _swapPrefix);
    _movePrefix(_prefix(current), _prefix(slot));
    if (occupant != null) _movePrefix(_swapPrefix, _prefix(current));

    final next = Map.of(slots.slots);
    next[modName] = slot;
    if (occupant != null) next[occupant] = current;
    await slots.save(next);
  }

  /// Removes [modName]'s files from the game folder and frees its slot.
  Future<void> disable(String modName) async {
    final slot = slotOf(modName);
    if (slot == null) return;

    for (final file in _filesOfSlot(slot)) {
      file.deleteSync();
    }

    final next = Map.of(slots.slots)..remove(modName);
    await slots.save(next);
  }

  Future<void> _installInto(int slot, String modName, String modDir) async {
    final archives = _archivesIn(modDir);
    if (archives.isEmpty) {
      throw StateError('Mod "$modName" contains no .vpk file');
    }

    Directory(addonsDir).createSync(recursive: true);
    for (final file in _filesOfSlot(slot)) {
      file.deleteSync();
    }

    final prefix = _prefix(slot);
    for (final archive in archives) {
      final target = p.join(addonsDir, '$prefix${_suffixOf(archive)}');
      File(archive).copySync(target);
    }

    await slots.save(Map.of(slots.slots)..[modName] = slot);
  }

  /// `.vpk` files of a mod folder, index first so it is copied first.
  List<String> _archivesIn(String modDir) {
    final dir = Directory(modDir);
    if (!dir.existsSync()) return const [];

    final archives = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((path) => p.extension(path).toLowerCase() == '.vpk')
        .toList()
      ..sort();

    return archives;
  }

  /// `skin_dir.vpk` -> `_dir.vpk`, `skin_000.vpk` -> `_000.vpk`.
  ///
  /// A mod shipped as one plain `skin.vpk` becomes the index, because that is
  /// what a single-archive mod is.
  static String _suffixOf(String archivePath) {
    final name = p.basenameWithoutExtension(archivePath);
    final match = RegExp(r'_(dir|\d{3})$').firstMatch(name);

    return match == null ? '_dir.vpk' : '_${match.group(1)}.vpk';
  }

  static String _prefix(int slot) => 'pak${slot.toString().padLeft(2, '0')}';

  /// Deliberately not a `pakNN` name, so a crash mid-swap leaves files the
  /// engine ignores rather than a mod loading under the wrong number.
  static const String _swapPrefix = 'modlinq-swap';

  List<File> _filesOfSlot(int slot) {
    final dir = Directory(addonsDir);
    if (!dir.existsSync()) return const [];

    final prefix = _prefix(slot);
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('${prefix}_'))
        .toList();
  }

  void _movePrefix(String from, String to) {
    final dir = Directory(addonsDir);
    if (!dir.existsSync()) return;

    for (final file in dir.listSync().whereType<File>()) {
      final name = p.basename(file.path);
      if (!name.startsWith('${from}_')) continue;

      file.renameSync(p.join(addonsDir, name.replaceFirst(from, to)));
    }
  }

  int _nextFreeSlot() {
    final taken = slots.slots.values.toSet();

    for (var slot = 1; slot <= maxSlot; slot++) {
      if (!taken.contains(slot)) return slot;
    }

    throw StateError(
      'Deadlock only loads $maxSlot mods at once, disable one first',
    );
  }
}
