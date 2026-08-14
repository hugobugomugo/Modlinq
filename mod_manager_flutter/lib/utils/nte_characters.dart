import 'zzz_characters.dart';

/// Playable Espers in Neverness to Everness, including announced ones.
const List<CharacterData> nteCharactersData = [
  CharacterData(id: 'adler', displayName: 'Adler', assetName: 'adler'),
  CharacterData(id: 'aurelia', displayName: 'Aurelia', assetName: 'aurelia'),
  CharacterData(id: 'baicang', displayName: 'Baicang', assetName: 'baicang'),
  CharacterData(id: 'chaos', displayName: 'Chaos', assetName: 'chaos'),
  CharacterData(id: 'chiz', displayName: 'Chiz', assetName: 'chiz'),
  CharacterData(id: 'daffodil', displayName: 'Daffodil', assetName: 'daffodil'),
  CharacterData(id: 'edgar', displayName: 'Edgar', assetName: 'edgar'),
  CharacterData(id: 'fadia', displayName: 'Fadia', assetName: 'fadia'),
  CharacterData(id: 'haniel', displayName: 'Haniel', assetName: 'haniel'),
  CharacterData(id: 'hathor', displayName: 'Hathor', assetName: 'hathor'),
  CharacterData(id: 'hotori', displayName: 'Hotori', assetName: 'hotori'),
  CharacterData(id: 'iroi', displayName: 'Iroi', assetName: 'iroi'),
  CharacterData(id: 'jiuyuan', displayName: 'Jiuyuan', assetName: 'jiuyuan'),
  CharacterData(id: 'lacrimosa', displayName: 'Lacrimosa', assetName: 'lacrimosa'),
  CharacterData(id: 'linko', displayName: 'Linko', assetName: 'linko'),
  CharacterData(id: 'mint', displayName: 'Mint', assetName: 'mint'),
  CharacterData(id: 'nanally', displayName: 'Nanally', assetName: 'nanally'),
  CharacterData(id: 'sakiri', displayName: 'Sakiri', assetName: 'sakiri'),
  CharacterData(id: 'shinku', displayName: 'Shinku', assetName: 'shinku'),
  CharacterData(id: 'skia', displayName: 'Skia', assetName: 'skia'),
  CharacterData(id: 'zankou', displayName: 'Zankou', assetName: 'zankou'),
  CharacterData(id: 'zero', displayName: 'Esper Zero', assetName: 'zero'),
];

const List<String> nteCharacters = [
  'adler', 'aurelia', 'baicang', 'chaos', 'chiz', 'daffodil', 'edgar', 'fadia',
  'haniel', 'hathor', 'hotori', 'iroi', 'jiuyuan', 'lacrimosa', 'linko', 'mint',
  'nanally', 'sakiri', 'shinku', 'skia', 'zankou', 'zero',
];

/// Name fragments that identify a character in a mod folder name.
///
/// Longer, more specific aliases must come first so a mod like
/// "gothycatmint_black_hair" is not matched by a shorter alias first.
const Map<String, List<String>> nteCharacterAliases = {
  'mint': ['gothycatmint', 'catmint', 'mint'],
  'nanally': ['nanally', 'nanaly'],
  'lacrimosa': ['lacrimosa'],
  'jiuyuan': ['jiuyuan', 'jiuyan'],
  'daffodil': ['daffodill', 'daffodil'],
  'chiz': ['chiz'],
  'baicang': ['baicang'],
  'sakiri': ['sakiri'],
  'fadia': ['fadia'],
  'hathor': ['hathor'],
  'hotori': ['hotori'],
  'chaos': ['chaos'],
  'shinku': ['shinku'],
  'iroi': ['iroi'],
  'zankou': ['zankou', 'zanku'],
  'linko': ['linko'],
  'edgar': ['edgar'],
  'adler': ['adler'],
  'haniel': ['haniel'],
  'skia': ['skia'],
  'aurelia': ['aurelia'],
  'zero': ['esper zero', 'esperzero'],
};

String getNteCharacterDisplayName(String id) {
  final character = nteCharactersData.firstWhere(
    (char) => char.id == id.toLowerCase(),
    orElse: () => CharacterData(id: id, displayName: id, assetName: id),
  );
  return character.displayName;
}

/// Finds the character a mod belongs to from its folder name.
///
/// Mod names put the character they change first, as in
/// "lacrimosa_nanallynightyoutfit" — a Lacrimosa mod borrowing Nanally's
/// outfit. So when several characters appear, the earliest one wins, and a
/// longer alias breaks a tie at the same position.
///
/// Returns null when nothing matches, which puts the mod in the unknown bucket
/// rather than guessing.
String? detectNteCharacter(String modName) {
  final normalized = modName.toLowerCase().replaceAll(RegExp(r'[_\-]+'), ' ');

  String? bestId;
  var bestIndex = -1;
  var bestLength = 0;

  for (final entry in nteCharacterAliases.entries) {
    for (final alias in entry.value) {
      final index = normalized.indexOf(alias);
      if (index == -1) continue;

      final isEarlier = bestId == null || index < bestIndex;
      final isLongerAtSamePosition = index == bestIndex && alias.length > bestLength;

      if (isEarlier || isLongerAtSamePosition) {
        bestId = entry.key;
        bestIndex = index;
        bestLength = alias.length;
      }
    }
  }

  return bestId;
}
