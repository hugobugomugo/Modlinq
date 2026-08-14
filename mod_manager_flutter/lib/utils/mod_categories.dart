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
}
