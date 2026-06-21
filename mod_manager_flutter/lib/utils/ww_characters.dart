import 'zzz_characters.dart';

/// List of all available resonators in Wuthering Waves
const List<CharacterData> wwCharactersData = [
  CharacterData(id: 'aalto', displayName: 'Aalto', assetName: 'aalto'),
  CharacterData(id: 'baizhi', displayName: 'Baizhi', assetName: 'baizhi'),
  CharacterData(id: 'brant', displayName: 'Brant', assetName: 'brant'),
  CharacterData(id: 'calcharo', displayName: 'Calcharo', assetName: 'calcharo'),
  CharacterData(id: 'camellya', displayName: 'Camellya', assetName: 'camellya'),
  CharacterData(id: 'cantarella', displayName: 'Cantarella', assetName: 'cantarella'),
  CharacterData(id: 'carlotta', displayName: 'Carlotta', assetName: 'carlotta'),
  CharacterData(id: 'changli', displayName: 'Changli', assetName: 'changli'),
  CharacterData(id: 'chixia', displayName: 'Chixia', assetName: 'chixia'),
  CharacterData(id: 'ciaccona', displayName: 'Ciaccona', assetName: 'ciaccona'),
  CharacterData(id: 'danjin', displayName: 'Danjin', assetName: 'danjin'),
  CharacterData(id: 'encore', displayName: 'Encore', assetName: 'encore'),
  CharacterData(id: 'jianxin', displayName: 'Jianxin', assetName: 'jianxin'),
  CharacterData(id: 'jiyan', displayName: 'Jiyan', assetName: 'jiyan'),
  CharacterData(id: 'jinhsi', displayName: 'Jinhsi', assetName: 'jinhsi'),
  CharacterData(id: 'lingyang', displayName: 'Lingyang', assetName: 'lingyang'),
  CharacterData(id: 'lumi', displayName: 'Lumi', assetName: 'lumi'),
  CharacterData(id: 'mortefi', displayName: 'Mortefi', assetName: 'mortefi'),
  CharacterData(id: 'phoebe', displayName: 'Phoebe', assetName: 'phoebe'),
  CharacterData(id: 'roccia', displayName: 'Roccia', assetName: 'roccia'),
  CharacterData(id: 'rover_spectro', displayName: 'Rover (Spectro)', assetName: 'rover_spectro'),
  CharacterData(id: 'rover_havoc', displayName: 'Rover (Havoc)', assetName: 'rover_havoc'),
  CharacterData(id: 'sanhua', displayName: 'Sanhua', assetName: 'sanhua'),
  CharacterData(id: 'shorekeeper', displayName: 'Shorekeeper', assetName: 'shorekeeper'),
  CharacterData(id: 'taoqi', displayName: 'Taoqi', assetName: 'taoqi'),
  CharacterData(id: 'verina', displayName: 'Verina', assetName: 'verina'),
  CharacterData(id: 'xiangliyao', displayName: 'Xiangli Yao', assetName: 'xiangliyao'),
  CharacterData(id: 'yinlin', displayName: 'Yinlin', assetName: 'yinlin'),
  CharacterData(id: 'youhu', displayName: 'Youhu', assetName: 'youhu'),
  CharacterData(id: 'yuanwu', displayName: 'Yuanwu', assetName: 'yuanwu'),
  CharacterData(id: 'zani', displayName: 'Zani', assetName: 'zani'),
  CharacterData(id: 'zhezhi', displayName: 'Zhezhi', assetName: 'zhezhi'),
];

const List<String> wwCharacters = [
  'aalto', 'baizhi', 'brant', 'calcharo', 'camellya', 'cantarella', 'carlotta',
  'changli', 'chixia', 'ciaccona', 'danjin', 'encore', 'jianxin', 'jiyan',
  'jinhsi', 'lingyang', 'lumi', 'mortefi', 'phoebe', 'roccia',
  'rover_spectro', 'rover_havoc', 'sanhua', 'shorekeeper', 'taoqi', 'verina',
  'xiangliyao', 'yinlin', 'youhu', 'yuanwu', 'zani', 'zhezhi',
];

String getWwCharacterDisplayName(String id) {
  final character = wwCharactersData.firstWhere(
    (char) => char.id == id.toLowerCase(),
    orElse: () => CharacterData(id: id, displayName: id, assetName: id),
  );
  return character.displayName;
}

String getWwCharacterAssetName(String id) {
  final character = wwCharactersData.firstWhere(
    (char) => char.id == id.toLowerCase(),
    orElse: () => CharacterData(id: id, displayName: id, assetName: id),
  );
  return character.assetName;
}
