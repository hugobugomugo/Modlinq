import 'dart:io';
import 'package:path/path.dart' as path;
import '../models/keybind_info.dart';

class IniParserService {
  static final RegExp _sectionRegex = RegExp(r'^\[([^\]]+)\]$');
  
  static final RegExp _keyValueRegex = RegExp(r'^([^=]+)=(.*)$');
  
  static const List<String> keybindSections = [
    'keyswap',
    'keyup',
    'keydown',
    'keyleft',
    'keyright',
    'keypress',
    'keybind',
    'keybinds',
    'hotkey',
    'hotkeys',
  ];

  Future<List<KeybindInfo>> parseIniFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return [];
      }

      final lines = await file.readAsLines();
      final keybinds = <KeybindInfo>[];
      String? currentSection;
      final currentKeys = <String, String>{};

      for (var line in lines) {
        line = line.trim();

        if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) {
          continue;
        }

        final sectionMatch = _sectionRegex.firstMatch(line);
        if (sectionMatch != null) {
          if (currentSection != null && _isKeybindSection(currentSection)) {
            if (currentKeys.isNotEmpty) {
              keybinds.add(KeybindInfo(
                section: currentSection,
                keys: Map.from(currentKeys),
              ));
              currentKeys.clear();
            }
          }

          currentSection = sectionMatch.group(1);
          continue;
        }

        final keyValueMatch = _keyValueRegex.firstMatch(line);
        if (keyValueMatch != null && currentSection != null) {
          final key = keyValueMatch.group(1)?.trim() ?? '';
          final value = keyValueMatch.group(2)?.trim() ?? '';
          
          if (key.isNotEmpty) {
            currentKeys[key] = value;
          }
        }
      }

      if (currentSection != null && _isKeybindSection(currentSection)) {
        if (currentKeys.isNotEmpty) {
          keybinds.add(KeybindInfo(
            section: currentSection,
            keys: Map.from(currentKeys),
          ));
        }
      }

      return keybinds;
    } catch (e) {
      print('IniParserService: ini file parse failed $filePath: $e');
      return [];
    }
  }

  bool _isKeybindSection(String sectionName) {
    final lowerSection = sectionName.toLowerCase();
    if (lowerSection.startsWith('key')) {
      return true;
    }
    return keybindSections.any((keyword) => lowerSection.contains(keyword));
  }

  Future<List<String>> findIniFiles(String directoryPath) async {
    try {
      final dir = Directory(directoryPath);
      if (!await dir.exists()) {
        print('IniParserService: directory does not exist: $directoryPath');
        return [];
      }

      final iniFiles = <String>[];
      
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.ini')) {
          print('IniParserService: found ini file: ${entity.path}');
          iniFiles.add(entity.path);
        }
      }

      print('IniParserService: found ${iniFiles.length} ini files in $directoryPath');
      return iniFiles;
    } catch (e) {
      print('IniParserService: ini file search failed in $directoryPath: $e');
      return [];
    }
  }

  Future<CharacterKeybinds?> parseCharacterDirectory(
    String characterId,
    String directoryPath,
  ) async {
    try {
      final iniFiles = await findIniFiles(directoryPath);
      if (iniFiles.isEmpty) {
        return null;
      }

      final allKeybinds = <KeybindInfo>[];

      for (final iniFile in iniFiles) {
        final keybinds = await parseIniFile(iniFile);
        allKeybinds.addAll(keybinds);
      }

      if (allKeybinds.isEmpty) {
        return null;
      }

      return CharacterKeybinds(
        characterId: characterId,
        keybinds: allKeybinds,
        iniFilePath: iniFiles.first,
      );
    } catch (e) {
      print('IniParserService: directory parse failed $directoryPath: $e');
      return null;
    }
  }

  Future<Map<String, CharacterKeybinds>> parseAllCharacters(
    String saveModsPath,
  ) async {
    try {
      final saveModsDir = Directory(saveModsPath);
      if (!await saveModsDir.exists()) {
        print('IniParserService: saveModsPath does not exist: $saveModsPath');
        return {};
      }

      final characterKeybinds = <String, CharacterKeybinds>{};
      print('IniParserService: scanning $saveModsPath for keybinds...');

      await for (final entity in saveModsDir.list()) {
        if (entity is Directory) {
          final characterId = path.basename(entity.path);
          
          if (characterId.startsWith('.') || characterId.startsWith('__')) {
            continue;
          }

          print('IniParserService: checking folder $characterId...');
          final keybinds = await parseCharacterDirectory(
            characterId,
            entity.path,
          );

          if (keybinds != null) {
            print('IniParserService: found ${keybinds.keybinds.length} keybinds for $characterId');
            characterKeybinds[characterId] = keybinds;
          } else {
            print('IniParserService: no ini files found in $characterId');
          }
        }
      }

      print('IniParserService: keybinds found for ${characterKeybinds.length} folders total');
      return characterKeybinds;
    } catch (e) {
      print('IniParserService: parsing all characters failed in $saveModsPath: $e');
      return {};
    }
  }
}
