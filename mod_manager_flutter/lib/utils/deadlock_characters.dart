import 'zzz_characters.dart';

/// Playable heroes in Deadlock.
///
/// Mirrors the roster files of the other games. The ids are GameBanana's
/// subcategory names slugged, so a marketplace mod tagged "Grey Talon" maps
/// onto `grey_talon` without a second table.
///
/// Icons live in `assets/characters_deadlock/<id>.png`. Valve's hero art sits
/// in the game's VPKs as compiled textures, so GameBanana's 40x40 category
/// icons are no help; `scripts/fetch_deadlock_icons.py` pulls the same
/// portraits Valve uses in the hero picker and squares them off. Rerun it
/// after adding a hero here.
const List<CharacterData> deadlockCharactersData = [
  CharacterData(id: 'abrams', displayName: 'Abrams', assetName: 'abrams'),
  CharacterData(id: 'apollo', displayName: 'Apollo', assetName: 'apollo'),
  CharacterData(id: 'baba', displayName: 'Baba', assetName: 'baba'),
  CharacterData(id: 'bebop', displayName: 'Bebop', assetName: 'bebop'),
  CharacterData(id: 'billy', displayName: 'Billy', assetName: 'billy'),
  CharacterData(id: 'calico', displayName: 'Calico', assetName: 'calico'),
  CharacterData(id: 'celeste', displayName: 'Celeste', assetName: 'celeste'),
  CharacterData(id: 'deadman_danny', displayName: 'Deadman Danny', assetName: 'deadman_danny'),
  CharacterData(id: 'doorman', displayName: 'Doorman', assetName: 'doorman'),
  CharacterData(id: 'drifter', displayName: 'Drifter', assetName: 'drifter'),
  CharacterData(id: 'dynamo', displayName: 'Dynamo', assetName: 'dynamo'),
  CharacterData(id: 'graves', displayName: 'Graves', assetName: 'graves'),
  CharacterData(id: 'grey_talon', displayName: 'Grey Talon', assetName: 'grey_talon'),
  CharacterData(id: 'haze', displayName: 'Haze', assetName: 'haze'),
  CharacterData(id: 'holliday', displayName: 'Holliday', assetName: 'holliday'),
  CharacterData(id: 'infernus', displayName: 'Infernus', assetName: 'infernus'),
  CharacterData(id: 'ivy', displayName: 'Ivy', assetName: 'ivy'),
  CharacterData(id: 'kelvin', displayName: 'Kelvin', assetName: 'kelvin'),
  CharacterData(id: 'lady_geist', displayName: 'Lady Geist', assetName: 'lady_geist'),
  CharacterData(id: 'lash', displayName: 'Lash', assetName: 'lash'),
  CharacterData(id: 'mcginnis', displayName: 'McGinnis', assetName: 'mcginnis'),
  CharacterData(id: 'mina', displayName: 'Mina', assetName: 'mina'),
  CharacterData(id: 'mirage', displayName: 'Mirage', assetName: 'mirage'),
  CharacterData(id: 'mo_krill', displayName: 'Mo & Krill', assetName: 'mo_krill'),
  CharacterData(id: 'nurse_harrow', displayName: 'Nurse Harrow', assetName: 'nurse_harrow'),
  CharacterData(id: 'paige', displayName: 'Paige', assetName: 'paige'),
  CharacterData(id: 'paradox', displayName: 'Paradox', assetName: 'paradox'),
  CharacterData(id: 'pocket', displayName: 'Pocket', assetName: 'pocket'),
  CharacterData(id: 'ratking', displayName: 'RatKing', assetName: 'ratking'),
  CharacterData(id: 'rem', displayName: 'Rem', assetName: 'rem'),
  CharacterData(id: 'seven', displayName: 'Seven', assetName: 'seven'),
  CharacterData(id: 'shiv', displayName: 'Shiv', assetName: 'shiv'),
  CharacterData(id: 'silver', displayName: 'Silver', assetName: 'silver'),
  CharacterData(id: 'sinclair', displayName: 'Sinclair', assetName: 'sinclair'),
  CharacterData(id: 'solomon', displayName: 'Solomon', assetName: 'solomon'),
  CharacterData(id: 'venator', displayName: 'Venator', assetName: 'venator'),
  CharacterData(id: 'victor', displayName: 'Victor', assetName: 'victor'),
  CharacterData(id: 'vindicta', displayName: 'Vindicta', assetName: 'vindicta'),
  CharacterData(id: 'violet', displayName: 'Violet', assetName: 'violet'),
  CharacterData(id: 'viscous', displayName: 'Viscous', assetName: 'viscous'),
  CharacterData(id: 'vyper', displayName: 'Vyper', assetName: 'vyper'),
  CharacterData(id: 'warden', displayName: 'Warden', assetName: 'warden'),
  CharacterData(id: 'wraith', displayName: 'Wraith', assetName: 'wraith'),
  CharacterData(id: 'yamato', displayName: 'Yamato', assetName: 'yamato'),
];

const List<String> deadlockCharacters = [
  'abrams', 'apollo', 'baba', 'bebop', 'billy', 'calico', 'celeste',
  'deadman_danny', 'doorman', 'drifter', 'dynamo', 'graves', 'grey_talon',
  'haze', 'holliday', 'infernus', 'ivy', 'kelvin', 'lady_geist', 'lash',
  'mcginnis', 'mina', 'mirage', 'mo_krill', 'nurse_harrow', 'paige',
  'paradox', 'pocket', 'ratking', 'rem', 'seven', 'shiv', 'silver',
  'sinclair', 'solomon', 'venator', 'victor', 'vindicta', 'violet',
  'viscous', 'vyper', 'warden', 'wraith', 'yamato',
];

/// Name fragments that identify a hero in a mod folder name.
///
/// Longer aliases come first so "Grey Talon" is not claimed by a hero whose
/// name is a substring of it.
const Map<String, List<String>> deadlockCharacterAliases = {
  'deadman_danny': ['deadman danny', 'danny'],
  'nurse_harrow': ['nurse harrow', 'harrow'],
  'grey_talon': ['grey talon', 'talon'],
  'lady_geist': ['lady geist', 'geist'],
  'mo_krill': ['mo & krill', 'mo krill', 'krill'],
  'holliday': ['holliday'],
  'infernus': ['infernus'],
  'mcginnis': ['mcginnis'],
  'sinclair': ['sinclair'],
  'vindicta': ['vindicta', 'dicta'],
  'celeste': ['celeste'],
  'doorman': ['doorman'],
  'drifter': ['drifter'],
  'paradox': ['paradox'],
  'ratking': ['ratking'],
  'solomon': ['solomon'],
  'venator': ['venator'],
  'viscous': ['viscous'],
  'abrams': ['abrams'],
  'apollo': ['apollo'],
  'calico': ['calico'],
  'dynamo': ['dynamo'],
  'graves': ['graves'],
  'kelvin': ['kelvin'],
  'mirage': ['mirage'],
  'pocket': ['pocket'],
  'silver': ['silver'],
  'victor': ['victor'],
  'violet': ['violet'],
  'warden': ['warden'],
  'wraith': ['wraith'],
  'yamato': ['yamato'],
  'bebop': ['bebop'],
  'billy': ['billy'],
  'paige': ['paige'],
  'seven': ['seven'],
  'vyper': ['vyper'],
  'baba': ['baba'],
  'haze': ['haze'],
  'lash': ['lash'],
  'mina': ['mina'],
  'shiv': ['shiv'],
  'ivy': ['ivy'],
  'rem': ['rem'],
};

String getDeadlockCharacterDisplayName(String id) {
  final character = deadlockCharactersData.firstWhere(
    (char) => char.id == id.toLowerCase(),
    orElse: () => CharacterData(id: id, displayName: id, assetName: id),
  );
  return character.displayName;
}

/// How much of a word an alias has to own before it counts as that hero.
///
/// Mod folders glue words together - `baronessmina`, `silverbase`,
/// `variationgeistcombined` - so matching whole words only filed most of a
/// real library under unknown. How far a match may reach into a word depends
/// on how distinctive the alias is:
///
/// * five letters or more is unmistakable, so it matches anywhere in a word;
/// * four letters must sit at the start or the end of one, which still takes
///   `minaheels` and `baronessmina` while leaving `sparxie main` alone;
/// * three letters have to be the whole word, because "rem" would otherwise
///   claim every remaster and "ivy" every ivory.
RegExp _aliasPattern(String alias) {
  final body = RegExp.escape(alias);

  if (alias.length >= 5) return RegExp(body);
  if (alias.length == 4) {
    return RegExp('(?:(?<![a-z0-9])$body|$body(?![a-z0-9]))');
  }

  return RegExp('(?<![a-z0-9])$body(?![a-z0-9])');
}

/// Finds the hero a mod belongs to from its folder name.
///
/// Earliest match wins and a longer alias breaks a tie at the same position,
/// so "Yamato remodel" stays with Yamato. No match returns null and the mod
/// lands in the unknown bucket instead of under a wrong hero.
String? detectDeadlockCharacter(String modName) {
  final normalized = modName.toLowerCase().replaceAll(RegExp(r'[_\-]+'), ' ');

  String? bestId;
  var bestIndex = -1;
  var bestLength = 0;

  for (final entry in deadlockCharacterAliases.entries) {
    for (final alias in entry.value) {
      final match = _aliasPattern(alias).firstMatch(normalized);
      if (match == null) continue;

      final index = match.start;
      final isEarlier = bestId == null || index < bestIndex;
      final isLongerAtSamePosition =
          index == bestIndex && alias.length > bestLength;

      if (isEarlier || isLongerAtSamePosition) {
        bestId = entry.key;
        bestIndex = index;
        bestLength = alias.length;
      }
    }
  }

  return bestId;
}
