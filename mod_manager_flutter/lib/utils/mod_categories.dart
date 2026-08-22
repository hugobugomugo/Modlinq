/// Buckets that hold mods which do not belong to a single character.
///
/// Both appear alongside the character cards in every game.
class ModCategories {
  /// Game-wide mods the user has deliberately grouped here, such as RabbitFX
  /// or UI replacements. Assigned by hand, so the card is always shown as a
  /// drop target even when empty.
  static const String misc = 'misc';

  /// Mods whose name matched no character. Filled automatically, and shown
  /// only when something landed in it.
  static const String unknown = 'unknown';

  static const Set<String> all = {misc, unknown};

  static bool isSpecial(String characterId) => all.contains(characterId);

  /// The character id a mod card should print in its corner, or null when
  /// there is nothing worth showing.
  ///
  /// [assignedTag] is the tag the user set by hand, which ZZZ and WUWA keep in
  /// their tag map. NTE stores no such tag and instead resolves the character
  /// from the folder name into [characterId], so the fallback is what gives
  /// every game the same label.
  static String? badgeIdFor({
    required String? assignedTag,
    required String characterId,
  }) {
    final id = (assignedTag != null && assignedTag.isNotEmpty)
        ? assignedTag
        : characterId;

    if (id.isEmpty || isSpecial(id)) return null;
    return id;
  }
}
