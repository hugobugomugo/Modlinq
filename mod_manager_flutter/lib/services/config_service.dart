import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../utils/path_helper.dart';

class ConfigService {
  static const String _keyModsPath = 'mods_path';
  static const String _keySaveModsPath = 'save_mods_path';
  static const String _keyWwModsPath = 'mods_path_ww';
  static const String _keyWwSaveModsPath = 'save_mods_path_ww';
  static const String _keyCurrentGame = 'current_game';
  static const String _keyActiveMods = 'active_mods';
  static const String _keyWwActiveMods = 'active_mods_ww';
  static const String _keyTheme = 'theme';
  static const String _keyLanguage = 'language';
  static const String _keyModCharacterTags = 'mod_character_tags';
  static const String _keyWwModCharacterTags = 'mod_character_tags_ww';
  static const String _keyFavoriteMods = 'favorite_mods';
  static const String _keyWwFavoriteMods = 'favorite_mods_ww';
  static const String _keyFirstRun = 'first_run';
  static const String _keyPersistModSettings = 'persist_mod_settings';
  static const String _keyModPersistStates = 'mod_persist_states';

  final SharedPreferences _prefs;
  File? _configFile;

  ConfigService(this._prefs) {
    _initConfigFile();
  }

  void _initConfigFile() {
    try {
      final appDataPath = PathHelper.getAppDataPath();
      final configPath = path.join(appDataPath, AppConstants.configFileName);
      _configFile = File(configPath);
      
      final dir = Directory(appDataPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
    } catch (e) {
      // fallback to cwd during dev
      final configPath = path.join(Directory.current.path, AppConstants.configFileName);
      _configFile = File(configPath);
    }
  }

  String get currentGame => _prefs.getString(_keyCurrentGame) ?? 'zzz';
  bool get isWutheringWaves => currentGame == 'ww';

  String? get modsPath => isWutheringWaves
      ? _prefs.getString(_keyWwModsPath)
      : _prefs.getString(_keyModsPath);
  String? get saveModsPath => isWutheringWaves
      ? _prefs.getString(_keyWwSaveModsPath)
      : _prefs.getString(_keySaveModsPath);

  String? get zzzModsPath => _prefs.getString(_keyModsPath);
  String? get zzzSaveModsPath => _prefs.getString(_keySaveModsPath);
  String? get wwModsPath => _prefs.getString(_keyWwModsPath);
  String? get wwSaveModsPath => _prefs.getString(_keyWwSaveModsPath);

  List<String> get activeMods => isWutheringWaves
      ? (_prefs.getStringList(_keyWwActiveMods) ?? [])
      : (_prefs.getStringList(_keyActiveMods) ?? []);
  List<String> get favoriteMods => isWutheringWaves
      ? (_prefs.getStringList(_keyWwFavoriteMods) ?? [])
      : (_prefs.getStringList(_keyFavoriteMods) ?? []);
  String get theme => _prefs.getString(_keyTheme) ?? 'dark-blue';
  String get language => _prefs.getString(_keyLanguage) ?? 'en';
  bool get isFirstRun => _prefs.getBool(_keyFirstRun) ?? true;
  bool get persistModSettings => _prefs.getBool(_keyPersistModSettings) ?? true;

  Future<bool> setPersistModSettings(bool value) async {
    try {
      await _prefs.setBool(_keyPersistModSettings, value);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Map<String, String>? getModPersistState(String modName) {
    final json = _prefs.getString(_keyModPersistStates);
    if (json == null) return null;
    try {
      final all = Map<String, dynamic>.from(jsonDecode(json));
      final entry = all[modName.toLowerCase()];
      if (entry == null) return null;
      return Map<String, String>.from(entry as Map);
    } catch (e) {
      return null;
    }
  }

  Future<void> saveModPersistState(String modName, Map<String, String> state) async {
    try {
      final json = _prefs.getString(_keyModPersistStates);
      final all = json != null ? Map<String, dynamic>.from(jsonDecode(json)) : <String, dynamic>{};
      all[modName.toLowerCase()] = state;
      await _prefs.setString(_keyModPersistStates, jsonEncode(all));
    } catch (e) {
      print('ConfigService: saveModPersistState error: $e');
    }
  }

  Future<void> clearModPersistState(String modName) async {
    try {
      final json = _prefs.getString(_keyModPersistStates);
      if (json == null) return;
      final all = Map<String, dynamic>.from(jsonDecode(json));
      all.remove(modName.toLowerCase());
      await _prefs.setString(_keyModPersistStates, jsonEncode(all));
    } catch (e) {
      print('ConfigService: clearModPersistState error: $e');
    }
  }

  String get _activeModsKey => isWutheringWaves ? _keyWwActiveMods : _keyActiveMods;
  String get _favoriteModsKey => isWutheringWaves ? _keyWwFavoriteMods : _keyFavoriteMods;
  String get _modCharacterTagsKey => isWutheringWaves ? _keyWwModCharacterTags : _keyModCharacterTags;

  Map<String, String> get modCharacterTags {
    final json = _prefs.getString(_modCharacterTagsKey);
    if (json == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(json));
    } catch (e) {
      return {};
    }
  }

  Future<bool> setCurrentGame(String game) async {
    try {
      await _prefs.setString(_keyCurrentGame, game);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setModsPath(String path) async {
    try {
      final key = isWutheringWaves ? _keyWwModsPath : _keyModsPath;
      await _prefs.setString(key, path);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setSaveModsPath(String path) async {
    try {
      final key = isWutheringWaves ? _keyWwSaveModsPath : _keySaveModsPath;
      await _prefs.setString(key, path);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setPaths(String modsPath, String saveModsPath) async {
    try {
      await _prefs.setString(_keyModsPath, modsPath);
      await _prefs.setString(_keySaveModsPath, saveModsPath);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setZzzPaths(String modsPath, String saveModsPath) async {
    try {
      await _prefs.setString(_keyModsPath, modsPath);
      await _prefs.setString(_keySaveModsPath, saveModsPath);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setWwPaths(String modsPath, String saveModsPath) async {
    try {
      await _prefs.setString(_keyWwModsPath, modsPath);
      await _prefs.setString(_keyWwSaveModsPath, saveModsPath);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> addActiveMod(String modId) async {
    try {
      final mods = activeMods;
      if (!mods.contains(modId)) {
        mods.add(modId);
        await _prefs.setStringList(_activeModsKey, mods);
        await _saveToFile();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> addFavoriteMod(String modId) async {
    try {
      final mods = favoriteMods;
      if (!mods.contains(modId)) {
        mods.add(modId);
        await _prefs.setStringList(_favoriteModsKey, mods);
        await _saveToFile();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeFavoriteMod(String modId) async {
    try {
      final mods = favoriteMods;
      mods.remove(modId);
      await _prefs.setStringList(_favoriteModsKey, mods);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeActiveMod(String modId) async {
    try {
      final mods = activeMods;
      mods.remove(modId);
      await _prefs.setStringList(_activeModsKey, mods);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setModCharacterTag(String modId, String characterId) async {
    try {
      final tags = modCharacterTags;
      tags[modId] = characterId;
      await _prefs.setString(_modCharacterTagsKey, jsonEncode(tags));
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> removeModCharacterTag(String modId) async {
    try {
      final tags = modCharacterTags;
      tags.remove(modId);
      await _prefs.setString(_modCharacterTagsKey, jsonEncode(tags));
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> cleanupInvalidTags(List<String> validModIds) async {
    try {
      final tags = modCharacterTags;
      final keysToRemove = <String>[];

      for (final modId in tags.keys) {
        if (!validModIds.contains(modId)) {
          keysToRemove.add(modId);
        }
      }

      for (final key in keysToRemove) {
        tags.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        await _prefs.setString(_modCharacterTagsKey, jsonEncode(tags));
        await _saveToFile();
      }
    } catch (e) {
      // ignore
    }
  }

  Future<bool> setTheme(String theme) async {
    try {
      await _prefs.setString(_keyTheme, theme);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setLanguage(String language) async {
    try {
      await _prefs.setString(_keyLanguage, language);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> setFirstRunComplete() async {
    try {
      await _prefs.setBool(_keyFirstRun, false);
      await _saveToFile();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> loadFromFile() async {
    try {
      if (_configFile == null || !await _configFile!.exists()) return false;

      final content = await _configFile!.readAsString();
      final Map<String, dynamic> config = jsonDecode(content);

      if (config.containsKey('current_game')) {
        await _prefs.setString(_keyCurrentGame, config['current_game']);
      }
      if (config.containsKey('mods_path')) {
        await _prefs.setString(_keyModsPath, config['mods_path']);
      }
      if (config.containsKey('save_mods_path')) {
        await _prefs.setString(_keySaveModsPath, config['save_mods_path']);
      }
      if (config.containsKey('mods_path_ww')) {
        await _prefs.setString(_keyWwModsPath, config['mods_path_ww']);
      }
      if (config.containsKey('save_mods_path_ww')) {
        await _prefs.setString(_keyWwSaveModsPath, config['save_mods_path_ww']);
      }
      if (config.containsKey('active_mods')) {
        final List<String> mods = List<String>.from(config['active_mods']);
        await _prefs.setStringList(_keyActiveMods, mods);
      }
      if (config.containsKey('theme')) {
        await _prefs.setString(_keyTheme, config['theme']);
      }
      if (config.containsKey('language')) {
        await _prefs.setString(_keyLanguage, config['language']);
      }
      if (config.containsKey('mod_character_tags')) {
        await _prefs.setString(_keyModCharacterTags, jsonEncode(config['mod_character_tags']));
      }
      if (config.containsKey('favorite_mods')) {
        final List<String> mods = List<String>.from(config['favorite_mods']);
        await _prefs.setStringList(_keyFavoriteMods, mods);
      }
      if (config.containsKey('favorite_mods_ww')) {
        final List<String> mods = List<String>.from(config['favorite_mods_ww']);
        await _prefs.setStringList(_keyWwFavoriteMods, mods);
      }
      if (config.containsKey('active_mods_ww')) {
        final List<String> mods = List<String>.from(config['active_mods_ww']);
        await _prefs.setStringList(_keyWwActiveMods, mods);
      }
      if (config.containsKey('mod_character_tags_ww')) {
        await _prefs.setString(_keyWwModCharacterTags, jsonEncode(config['mod_character_tags_ww']));
      }
      if (config.containsKey('first_run')) {
        await _prefs.setBool(_keyFirstRun, config['first_run']);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _saveToFile() async {
    try {
      if (_configFile == null) return false;

      final config = {
        'current_game': currentGame,
        'mods_path': _prefs.getString(_keyModsPath) ?? '',
        'save_mods_path': _prefs.getString(_keySaveModsPath) ?? '',
        'mods_path_ww': _prefs.getString(_keyWwModsPath) ?? '',
        'save_mods_path_ww': _prefs.getString(_keyWwSaveModsPath) ?? '',
        'active_mods': _prefs.getStringList(_keyActiveMods) ?? [],
        'active_mods_ww': _prefs.getStringList(_keyWwActiveMods) ?? [],
        'favorite_mods': _prefs.getStringList(_keyFavoriteMods) ?? [],
        'favorite_mods_ww': _prefs.getStringList(_keyWwFavoriteMods) ?? [],
        'theme': theme,
        'language': language,
        'mod_character_tags': (() {
          final json = _prefs.getString(_keyModCharacterTags);
          if (json == null) return <String, String>{};
          try { return Map<String, String>.from(jsonDecode(json)); } catch (e) { return <String, String>{}; }
        })(),
        'mod_character_tags_ww': (() {
          final json = _prefs.getString(_keyWwModCharacterTags);
          if (json == null) return <String, String>{};
          try { return Map<String, String>.from(jsonDecode(json)); } catch (e) { return <String, String>{}; }
        })(),
        'first_run': false,
        'persist_mod_settings': persistModSettings,
      };

      final jsonString = const JsonEncoder.withIndent('  ').convert(config);
      await _configFile!.writeAsString(jsonString);

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      await _prefs.clear();
      if (_configFile != null && await _configFile!.exists()) {
        await _configFile!.delete();
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
