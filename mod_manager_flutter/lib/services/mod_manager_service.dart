import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/character_info.dart';
import '../models/keybind_info.dart';
import '../core/constants.dart';
import '../utils/state_providers.dart';
import 'config_service.dart';
import 'platform_service.dart';
import 'platform_service_factory.dart';
import 'ini_parser_service.dart';

class ModManagerService {
  final ConfigService _configService;
  final PlatformService _platformService;
  final ProviderContainer _container;
  final IniParserService _iniParser;

  ModManagerService(this._configService, this._container)
      : _platformService = PlatformServiceFactory.getInstance(),
        _iniParser = IniParserService();

  String? get modsPath => _configService.modsPath;
  String? get saveModsPath => _configService.saveModsPath;

  Future<(bool, String)> validatePaths() async {
    final mods = modsPath;
    final saveMods = saveModsPath;

    if (mods == null || mods.isEmpty || saveMods == null || saveMods.isEmpty) {
      return (false, 'Paths not configured. Set them in Settings.');
    }

    final modsDir = Directory(mods);
    if (!await modsDir.exists()) {
      return (false, 'Mods folder does not exist: $mods');
    }

    final saveModsDir = Directory(saveMods);
    if (await saveModsDir.exists()) {
      final stat = await saveModsDir.stat();
      if (stat.type != FileSystemEntityType.directory) {
        return (false, 'Links path exists but is not a folder: $saveMods');
      }
    }

    return (true, '');
  }

  Future<List<String>> scanMods() async {
    try {
      final (valid, _) = await validatePaths();
      if (!valid) return [];

      final modsDir = Directory(modsPath!);
      if (!await modsDir.exists()) return [];

      final mods = <String>[];
      await for (final entity in modsDir.list()) {
        if (entity is Directory) {
          final name = path.basename(entity.path);
          if (!name.startsWith('.') && !name.startsWith('__')) {
            mods.add(name);
          }
        }
      }

      return mods;
    } catch (e) {
      return [];
    }
  }

  Future<List<ModInfo>> getModsInfo() async {
    try {
      final modNames = await scanMods();
      final modsInfo = <ModInfo>[];
      final favoriteSet = _configService.favoriteMods.toSet();

      await _cleanupInvalidLinks();

      for (final modName in modNames) {
        final isActive = await isModActive(modName);
        final imagePath = await _findModImage(modName);

        modsInfo.add(
          ModInfo(
            id: modName,
            name: modName,
            characterId: 'unknown',
            isActive: isActive,
            imagePath: imagePath,
            isFavorite: favoriteSet.contains(modName),
          ),
        );
      }

      return modsInfo;
    } catch (e) {
      return [];
    }
  }

  Future<void> _cleanupInvalidLinks() async {
    try {
      if (saveModsPath == null) return;

      final saveModsDir = Directory(saveModsPath!);
      if (!await saveModsDir.exists()) return;

      final modNames = await scanMods();
      final validModNames = Set<String>.from(modNames);

      await for (final entity in saveModsDir.list()) {
        if (entity is Link) {
          final linkName = path.basename(entity.path);
          
          if (!validModNames.contains(linkName)) {
            try {
              await entity.delete();
              await _configService.removeActiveMod(linkName);
            } catch (e) {
              // ignore delete errors
            }
          }
        }
      }
    } catch (e) {
      // ignore
    }
  }

  Future<bool> isModActive(String modName) async {
    try {
      if (saveModsPath == null) return false;

      final linkPath = path.join(saveModsPath!, modName);
      final exists = await FileSystemEntity.type(linkPath) != FileSystemEntityType.notFound;
      if (!exists) return false;

      return await _platformService.isModLink(linkPath);
    } catch (e) {
      return false;
    }
  }

  Future<bool> activateMod(String modName) async {
    try {
      final (valid, _) = await validatePaths();
      if (!valid) return false;

      final srcPath = path.join(modsPath!, modName);
      final dstPath = path.join(saveModsPath!, modName);

      final srcDir = Directory(srcPath);
      if (!await srcDir.exists()) return false;

      final saveModsDir = Directory(saveModsPath!);
      if (!await saveModsDir.exists()) {
        await saveModsDir.create(recursive: true);
      }

      final success = await _platformService.createModLink(srcPath, dstPath);
      if (!success) {
        print('ModManagerService: failed to create link for $modName');
        return false;
      }

      await _configService.addActiveMod(modName);

      if (_configService.persistModSettings) {
        await _restoreModPersistState(modName);
      } else {
        await _clearD3dxUserIniEntries(modName);
      }

      // F10 reload only reaches 3DMigoto in ZZZ.
      if (_container.read(autoF10ReloadProvider) &&
          _container.read(selectedGameProvider) == GameType.zzz) {
        await _platformService.sendF10ToGame();
      }

      return true;
    } catch (e) {
      print('ModManagerService: activateMod error: $e');
      return false;
    }
  }

  Future<bool> renameMod(String oldName, String newName) async {
    try {
      if (modsPath == null) return false;

      final trimmed = newName.trim();
      if (trimmed.isEmpty || trimmed == oldName) return false;

      final oldModPath = path.join(modsPath!, oldName);
      final newModPath = path.join(modsPath!, trimmed);

      final oldDir = Directory(oldModPath);
      if (!await oldDir.exists()) return false;

      final newDir = Directory(newModPath);
      if (await newDir.exists()) return false;

      final wasActive = await isModActive(oldName);

      // Remove old symlink before renaming the folder
      if (wasActive && saveModsPath != null) {
        final oldLinkPath = path.join(saveModsPath!, oldName);
        await _platformService.removeModLink(oldLinkPath);
        await _configService.removeActiveMod(oldName);
      }

      await oldDir.rename(newModPath);

      // Restore symlink under new name
      if (wasActive && saveModsPath != null) {
        final newLinkPath = path.join(saveModsPath!, trimmed);
        await _platformService.createModLink(newModPath, newLinkPath);
        await _configService.addActiveMod(trimmed);
      }

      // Migrate character tag
      final existingTag = _configService.modCharacterTags[oldName];
      if (existingTag != null) {
        await _configService.setModCharacterTag(trimmed, existingTag);
        await _configService.removeModCharacterTag(oldName);
      }

      // Migrate favorite
      final favorites = _configService.favoriteMods;
      if (favorites.contains(oldName)) {
        await _configService.removeFavoriteMod(oldName);
        await _configService.addFavoriteMod(trimmed);
      }

      return true;
    } catch (e) {
      print('ModManagerService: renameMod error: $e');
      return false;
    }
  }

  Future<bool> deleteMod(String modId) async {
    try {
      if (modsPath == null) return false;

      if (await isModActive(modId)) {
        await deactivateMod(modId);
      }

      await _configService.removeFavoriteMod(modId);

      final modDir = Directory(path.join(modsPath!, modId));
      if (await modDir.exists()) {
        await modDir.delete(recursive: true);
      }

      return true;
    } catch (e) {
      print('ModManagerService: deleteMod error: $e');
      return false;
    }
  }

  Future<bool> deactivateMod(String modName) async {
    try {
      if (saveModsPath == null) return false;

      final linkPath = path.join(saveModsPath!, modName);
      final exists = await FileSystemEntity.type(linkPath) != FileSystemEntityType.notFound;
      if (!exists) return false;

      final success = await _platformService.removeModLink(linkPath);
      if (!success) {
        print('ModManagerService: failed to remove link for $modName');
        return false;
      }

      await _configService.removeActiveMod(modName);

      if (_configService.persistModSettings) {
        await _snapshotModPersistState(modName);
      } else {
        await _resetModPersistDefaults(modName);
      }

      // F10 reload only reaches 3DMigoto in ZZZ.
      if (_container.read(autoF10ReloadProvider) &&
          _container.read(selectedGameProvider) == GameType.zzz) {
        await _platformService.sendF10ToGame();
      }

      return true;
    } catch (e) {
      print('ModManagerService: deactivateMod error: $e');
      return false;
    }
  }

  File? _d3dxUserIni() {
    if (saveModsPath == null) return null;
    return File(path.join(path.dirname(path.normalize(saveModsPath!)), 'd3dx_user.ini'));
  }

  Future<void> _snapshotModPersistState(String modName) async {
    try {
      final file = _d3dxUserIni();
      if (file == null || !await file.exists()) return;

      final prefix = r'$\mods\' + modName.toLowerCase() + r'\';
      final state = <String, String>{};
      for (final line in await file.readAsLines()) {
        final t = line.trim();
        if (t.startsWith(prefix) && t.contains(' = ')) {
          final eq = t.indexOf(' = ');
          state[t.substring(0, eq)] = t.substring(eq + 3);
        }
      }
      print('ModManagerService: snapshot for "$modName" captured ${state.length} entries (prefix: $prefix)');
      if (state.isNotEmpty) {
        await _configService.saveModPersistState(modName, state);
      }
    } catch (e) {
      print('ModManagerService: _snapshotModPersistState error: $e');
    }
  }

  Future<void> _restoreModPersistState(String modName) async {
    try {
      final saved = _configService.getModPersistState(modName);
      if (saved == null || saved.isEmpty) return;
      if (modsPath == null) return;

      final prefix = r'$\mods\' + modName.toLowerCase() + r'\';

      // Group saved entries by relative INI file path (lowercase keys from d3dx_user.ini)
      final byFile = <String, Map<String, String>>{};
      for (final entry in saved.entries) {
        if (!entry.key.startsWith(prefix)) continue;
        final remainder = entry.key.substring(prefix.length);
        final lastBackslash = remainder.lastIndexOf(r'\');
        if (lastBackslash < 0) continue;
        byFile.putIfAbsent(remainder.substring(0, lastBackslash), () => {})[remainder.substring(lastBackslash + 1)] = entry.value;
      }

      print('ModManagerService: restoring "$modName" across ${byFile.length} INI files');

      for (final fileEntry in byFile.entries) {
        final iniFile = await _findFileIgnoreCase(path.join(modsPath!, modName), fileEntry.key);
        if (iniFile == null) {
          print('ModManagerService: restore - not found: ${fileEntry.key}');
          continue;
        }

        final lines = await iniFile.readAsLines();
        bool modified = false;
        for (int i = 0; i < lines.length; i++) {
          final lower = lines[i].toLowerCase();
          if (!lower.contains('persist')) continue;
          for (final varEntry in fileEntry.value.entries) {
            if (lower.contains('\$${varEntry.key.toLowerCase()}')) {
              final eqIdx = lines[i].indexOf('=');
              if (eqIdx >= 0) {
                lines[i] = '${lines[i].substring(0, eqIdx + 1)} ${varEntry.value}';
                modified = true;
                break;
              }
            }
          }
        }

        if (modified) {
          await iniFile.writeAsString(lines.join('\n'));
          print('ModManagerService: updated defaults in ${iniFile.path}');
        }
      }

      // Clear d3dx_user.ini entries so INI defaults aren't overridden on reload
      await _clearD3dxUserIniEntries(modName);
    } catch (e) {
      print('ModManagerService: _restoreModPersistState error: $e');
    }
  }

  Future<File?> _findFileIgnoreCase(String dirPath, String relPath) async {
    try {
      final parts = relPath.replaceAll(r'\', '/').split('/');
      String currentPath = dirPath;
      for (final part in parts) {
        final dir = Directory(currentPath);
        if (!await dir.exists()) return null;
        final entries = await dir.list().toList();
        FileSystemEntity? match;
        for (final entry in entries) {
          if (path.basename(entry.path).toLowerCase() == part.toLowerCase()) {
            match = entry;
            break;
          }
        }
        if (match == null) return null;
        currentPath = match.path;
      }
      final f = File(currentPath);
      return await f.exists() ? f : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearD3dxUserIniEntries(String modName) async {
    try {
      final file = _d3dxUserIni();
      if (file == null || !await file.exists()) return;
      final prefix = r'$\mods\' + modName.toLowerCase() + r'\';
      final lines = await file.readAsLines();
      final filtered = lines.where((l) => !l.trimLeft().startsWith(prefix)).toList();
      if (filtered.length != lines.length) {
        await file.writeAsString(filtered.join('\n'));
      }
    } catch (e) {
      print('ModManagerService: _clearD3dxUserIniEntries error: $e');
    }
  }

  Future<void> _resetModPersistDefaults(String modName) async {
    try {
      if (modsPath != null) {
        final modDir = Directory(path.join(modsPath!, modName));
        if (await modDir.exists()) {
          await for (final entity in modDir.list(recursive: true)) {
            if (entity is! File || !entity.path.toLowerCase().endsWith('.ini')) continue;
            final lines = await entity.readAsLines();
            bool modified = false;
            for (int i = 0; i < lines.length; i++) {
              final lower = lines[i].toLowerCase();
              if (!lower.contains('persist') || !lines[i].contains('=')) continue;
              final eqIdx = lines[i].indexOf('=');
              if (lines[i].substring(eqIdx + 1).trim() != '0') {
                lines[i] = '${lines[i].substring(0, eqIdx + 1)} 0';
                modified = true;
              }
            }
            if (modified) {
              await entity.writeAsString(lines.join('\n'));
              print('ModManagerService: reset persist defaults in ${entity.path}');
            }
          }
        }
      }
      await _configService.clearModPersistState(modName);
      await _clearD3dxUserIniEntries(modName);
    } catch (e) {
      print('ModManagerService: _resetModPersistDefaults error: $e');
    }
  }

  Future<bool> toggleMod(String modName) async {
    final isActive = await isModActive(modName);
    return isActive ? await deactivateMod(modName) : await activateMod(modName);
  }

  Future<String?> _findModImage(String modName) async {
    try {
      final modPath = path.join(modsPath!, modName);
      final modDir = Directory(modPath);
      if (!await modDir.exists()) return null;

      for (final imageName in AppConstants.imageFileNames) {
        final imagePath = path.join(modPath, imageName);
        final imageFile = File(imagePath);
        if (await imageFile.exists()) return imagePath;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  Future<bool> reloadMods() async {
    return await _platformService.sendF10ToGame();
  }

  void showF10SetupInstructions() {
    _platformService.showSetupInstructions();
  }

  Future<void> installF10Dependencies() async {
    await _platformService.checkDependencies();
  }

  Future<(List<String>, Map<String, String>)> importMods(List<String> folderPaths) async {
    try {
      final (valid, _) = await validatePaths();
      if (!valid) return (<String>[], <String, String>{});

      final importedMods = <String>[];
      final autoTags = <String, String>{};
      final modsDir = Directory(modsPath!);

      if (!await modsDir.exists()) {
        await modsDir.create(recursive: true);
      }

      for (final folderPath in folderPaths) {
        final sourceDir = Directory(folderPath);
        if (!await sourceDir.exists()) continue;

        final modName = path.basename(folderPath);
        final targetPath = path.join(modsPath!, modName);
        final targetDir = Directory(targetPath);

        if (await targetDir.exists()) continue;

        await _copyDirectory(sourceDir, targetDir);
        importedMods.add(modName);

        final detectedChar = await _detectCharacterFromName(modName);
        if (detectedChar != null) {
          autoTags[modName] = detectedChar;
        }
      }

      return (importedMods, autoTags);
    } catch (e) {
      return (<String>[], <String, String>{});
    }
  }

  String _normalizeModName(String name) {
    // Insert space before an uppercase letter that follows a lowercase letter (CamelCase split)
    final camelExpanded = name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return camelExpanded
        .replaceAll(RegExp(r'[_\-\.\s]+'), ' ')
        .toLowerCase()
        .trim();
  }

  Future<String?> _detectCharacterFromName(String modName) async {
    final normalizedName = _normalizeModName(modName);
    try {
      final modsPath = _configService.modsPath;
      if (modsPath != null && modsPath.isNotEmpty) {
        final modPath = path.join(modsPath, modName);
        final modDir = Directory(modPath);
      
      if (await modDir.exists()) {
        final iniFiles = await modDir
            .list(recursive: true)
            .where((entity) => 
                entity is File && 
                path.extension(entity.path).toLowerCase() == '.ini')
            .cast<File>()
            .toList();
        
        for (final iniFile in iniFiles) {
          try {
            final content = await iniFile.readAsString();
            final charFromIni = _findCharacterInText(content.toLowerCase());
            if (charFromIni != null) {
              print('ModManager: detected "$charFromIni" from INI ${path.basename(iniFile.path)} in "$modName"');
              return charFromIni;
            }
          } catch (e) {
            // ignore unreadable files
          }
        }

        final subdirs = await modDir
            .list(recursive: false)
            .where((entity) => entity is Directory)
            .cast<Directory>()
            .toList();
        
        for (final subdir in subdirs) {
          final subdirName = _normalizeModName(path.basename(subdir.path));
          final charFromSubdir = _findCharacterInText(subdirName);
          if (charFromSubdir != null) {
            print('ModManager: detected "$charFromSubdir" from subdir "$subdirName" in "$modName"');
            return charFromSubdir;
          }
        }
      }
    }
    } catch (e) {
      print('ModManager: error scanning mod files for "$modName": $e');
    }

    final characterAliases = <String, List<String>>{
      'alice': ['alice', 'alice thymefield'],
      'anby': ['anby', 'anby demara'],
      'anton': ['anton', 'anton ivanov'],
      'aria': ['aria'],
      'astra': ['astra', 'astrayao', 'astra yao'],
      'banyue': ['banyue'],
      'belle': ['belle'],
      'ben': ['ben', 'ben bigger'],
      // NOTE: must precede 'billy' so "starlight billy" mods aren't tagged as billy
      'starlightbilly': ['starlightbilly', 'starlight billy', 'starlight-billy'],
      'billy': ['billy', 'billyherinkton', 'billy kid'],
      'burnice': ['burnice', 'burnice white'],
      'caesar': ['caesar', 'caesar king'],
      'cissia': ['cissia'],
      'corin': ['corin', 'corin wickes'],
      'dialyn': ['dialyn'],
      'ellen': ['ellen', 'ellen joe'],
      'evelyn': ['evelyn', 'evelyn chevalier'],
      'grace': ['grace', 'grace howard'],
      'harumasa': ['harumasa', 'asaba harumasa'],
      'hugo': ['hugo', 'hugo vlad'],
      'jane': ['jane', 'janedoe', 'jane doe'],
      'jufufu': ['jufufu', 'ju fufu'],
      'koleda': ['koleda', 'koleda belobog'],
      'lighter': ['lighter', 'lighter lorenz'],
      'lucia': ['lucia', 'lucia elowen'],
      'lucy': ['lucy', 'lucy kushinada'],
      'lycaon': ['lycaon', 'von lycaon', 'vonlycaon'],
      'manato': ['manato', 'komano manato'],
      'miyabi': ['miyabi', 'hoshimi miyabi'],
      'nangongyu': ['nangongyu', 'nangong yu'],
      'nekomata': ['nekomata', 'nekomiya mana'],
      'nicole': ['nicole', 'nicole demara'],
      'norma': ['norma', 'norma hollowell'],
      'orphie': ['orphie', 'orphiemagus', 'orphie magus', 'orphie magnusson'],
      'panyinhu': ['panyinhu', 'pan yinhu'],
      'piper': ['piper', 'piper wheel'],
      'promeia': ['promeia'],
      'pulchra': ['pulchra', 'pulchra fellini'],
      'pyrois': ['pyrois'],
      'quinqiy': ['quinqiy', 'qingyi'],
      'remielle': ['remielle', 'remielle dan'],
      'rina': ['rina', 'alexandrina', 'alexandrina sebastiane'],
      'seed': ['seed'],
      'seth': ['seth', 'seth lowell'],
      'sigrid': ['sigrid'],
      'solder0anby': ['solder0anby', 'soldier 0', 'soldier0'],
      'solder11': ['solder11', 'soldier 11', 'soldier11'],
      'soukaku': ['soukaku'],
      'sunna': ['sunna'],
      'trigger': ['trigger'],
      'velina': ['velina', 'velina airgid'],
      'vivian': ['vivian', 'vivian banshee'],
      'wise': ['wise'],
      'yanagi': ['yanagi', 'tsukishiro yanagi'],
      'yeshunguang': ['yeshunguang', 'ye shunguang', 'shunguang'],
      'yidhari': ['yidhari', 'yidhari murphy'],
      'yixuan': ['yixuan'],
      'yuzuha': ['yuzuha', 'ukinami yuzuha'],
      'zhao': ['zhao'],
      'zhuyuan': ['zhuyuan', 'zhu yuan'],
    };

    for (final entry in characterAliases.entries) {
      final charId = entry.key;
      for (final alias in entry.value) {
        final pattern = RegExp(r'\b' + RegExp.escape(alias) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(normalizedName)) {
          print('ModManager: detected "$charId" (alias: "$alias") in "$modName"');
          return charId;
        }
      }
    }

    // Wuthering Waves character aliases
    final wwCharacterAliases = <String, List<String>>{
      'aalto': ['aalto'],
      'baizhi': ['baizhi'],
      'brant': ['brant'],
      'calcharo': ['calcharo'],
      'camellya': ['camellya'],
      'cantarella': ['cantarella'],
      'carlotta': ['carlotta'],
      'changli': ['changli'],
      'chixia': ['chixia'],
      'ciaccona': ['ciaccona'],
      'danjin': ['danjin'],
      'encore': ['encore'],
      'jianxin': ['jianxin'],
      'jiyan': ['jiyan'],
      'jinhsi': ['jinhsi'],
      'lingyang': ['lingyang'],
      'lumi': ['lumi'],
      'mortefi': ['mortefi'],
      'phoebe': ['phoebe'],
      'roccia': ['roccia'],
      'rover_spectro': ['rover spectro', 'roverspectro', 'spectro rover'],
      'rover_havoc': ['rover havoc', 'roverhavoc', 'havoc rover'],
      'sanhua': ['sanhua'],
      'shorekeeper': ['shorekeeper'],
      'taoqi': ['taoqi'],
      'verina': ['verina'],
      'xiangliyao': ['xiangliyao', 'xiangli yao'],
      'yinlin': ['yinlin'],
      'youhu': ['youhu'],
      'yuanwu': ['yuanwu'],
      'zani': ['zani'],
      'zhezhi': ['zhezhi'],
    };

    for (final entry in wwCharacterAliases.entries) {
      final charId = entry.key;
      for (final alias in entry.value) {
        final pattern = RegExp(r'\b' + RegExp.escape(alias) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(normalizedName)) {
          print('ModManager: detected WW "$charId" (alias: "$alias") in "$modName"');
          return charId;
        }
      }
    }

    print('ModManager: no character detected for "$modName"');
    return null;
  }

  String? _findCharacterInText(String text) {
    final textLower = text.toLowerCase();
    
    final characterAliases = <String, List<String>>{
      'alice': ['alice', 'alice thymefield'],
      'anby': ['anby', 'anby demara'],
      'anton': ['anton', 'anton ivanov'],
      'aria': ['aria'],
      'astra': ['astra', 'astrayao', 'astra yao'],
      'banyue': ['banyue'],
      'belle': ['belle'],
      'ben': ['ben', 'ben bigger'],
      // NOTE: must precede 'billy' so "starlight billy" mods aren't tagged as billy
      'starlightbilly': ['starlightbilly', 'starlight billy', 'starlight-billy'],
      'billy': ['billy', 'billyherinkton', 'billy kid'],
      'burnice': ['burnice', 'burnice white'],
      'caesar': ['caesar', 'caesar king'],
      'cissia': ['cissia'],
      'corin': ['corin', 'corin wickes'],
      'dialyn': ['dialyn'],
      'ellen': ['ellen', 'ellen joe'],
      'evelyn': ['evelyn', 'evelyn chevalier'],
      'grace': ['grace', 'grace howard'],
      'harumasa': ['harumasa', 'asaba harumasa'],
      'hugo': ['hugo', 'hugo vlad'],
      'jane': ['jane', 'janedoe', 'jane doe'],
      'jufufu': ['jufufu', 'ju fufu'],
      'koleda': ['koleda', 'koleda belobog'],
      'lighter': ['lighter', 'lighter lorenz'],
      'lucia': ['lucia', 'lucia elowen'],
      'lucy': ['lucy', 'lucy kushinada'],
      'lycaon': ['lycaon', 'von lycaon', 'vonlycaon'],
      'manato': ['manato', 'komano manato'],
      'miyabi': ['miyabi', 'hoshimi miyabi'],
      'nangongyu': ['nangongyu', 'nangong yu'],
      'nekomata': ['nekomata', 'nekomiya mana'],
      'nicole': ['nicole', 'nicole demara'],
      'norma': ['norma', 'norma hollowell'],
      'orphie': ['orphie', 'orphiemagus', 'orphie magus', 'orphie magnusson'],
      'panyinhu': ['panyinhu', 'pan yinhu'],
      'piper': ['piper', 'piper wheel'],
      'promeia': ['promeia'],
      'pulchra': ['pulchra', 'pulchra fellini'],
      'pyrois': ['pyrois'],
      'quinqiy': ['quinqiy', 'qingyi'],
      'remielle': ['remielle', 'remielle dan'],
      'rina': ['rina', 'alexandrina', 'alexandrina sebastiane'],
      'seed': ['seed'],
      'seth': ['seth', 'seth lowell'],
      'sigrid': ['sigrid'],
      'solder0anby': ['solder0anby', 'soldier 0', 'soldier0'],
      'solder11': ['solder11', 'soldier 11', 'soldier11'],
      'soukaku': ['soukaku'],
      'sunna': ['sunna'],
      'trigger': ['trigger'],
      'velina': ['velina', 'velina airgid'],
      'vivian': ['vivian', 'vivian banshee'],
      'wise': ['wise'],
      'yanagi': ['yanagi', 'tsukishiro yanagi'],
      'yeshunguang': ['yeshunguang', 'ye shunguang', 'shunguang'],
      'yidhari': ['yidhari', 'yidhari murphy'],
      'yixuan': ['yixuan'],
      'yuzuha': ['yuzuha', 'ukinami yuzuha'],
      'zhao': ['zhao'],
      'zhuyuan': ['zhuyuan', 'zhu yuan'],
    };
    
    for (final entry in characterAliases.entries) {
      final charId = entry.key;
      for (final alias in entry.value) {
        final pattern = RegExp(r'\b' + RegExp.escape(alias) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(textLower)) return charId;
      }
    }

    // Wuthering Waves aliases
    const wwAliases = <String, List<String>>{
      'aalto': ['aalto'],
      'baizhi': ['baizhi'],
      'brant': ['brant'],
      'calcharo': ['calcharo'],
      'camellya': ['camellya'],
      'cantarella': ['cantarella'],
      'carlotta': ['carlotta'],
      'changli': ['changli'],
      'chixia': ['chixia'],
      'ciaccona': ['ciaccona'],
      'danjin': ['danjin'],
      'encore': ['encore'],
      'jianxin': ['jianxin'],
      'jiyan': ['jiyan'],
      'jinhsi': ['jinhsi'],
      'lingyang': ['lingyang'],
      'lumi': ['lumi'],
      'mortefi': ['mortefi'],
      'phoebe': ['phoebe'],
      'roccia': ['roccia'],
      'rover_spectro': ['rover spectro', 'roverspectro'],
      'rover_havoc': ['rover havoc', 'roverhavoc'],
      'sanhua': ['sanhua'],
      'shorekeeper': ['shorekeeper'],
      'taoqi': ['taoqi'],
      'verina': ['verina'],
      'xiangliyao': ['xiangliyao', 'xiangli yao'],
      'yinlin': ['yinlin'],
      'youhu': ['youhu'],
      'yuanwu': ['yuanwu'],
      'zani': ['zani'],
      'zhezhi': ['zhezhi'],
    };

    for (final entry in wwAliases.entries) {
      for (final alias in entry.value) {
        final pattern = RegExp(r'\b' + RegExp.escape(alias) + r'\b', caseSensitive: false);
        if (pattern.hasMatch(textLower)) return entry.key;
      }
    }

    return null;
  }

  Future<Map<String, String>> autoTagAllMods() async {
    try {
      final modNames = await scanMods();
      final autoTags = <String, String>{};

      for (final modName in modNames) {
        final existingTag = _configService.modCharacterTags[modName];
        if (existingTag != null && existingTag != 'unknown') continue;

        final detectedChar = await _detectCharacterFromName(modName);
        if (detectedChar != null) {
          await _configService.setModCharacterTag(modName, detectedChar);
          autoTags[modName] = detectedChar;
        }
      }

      return autoTags;
    } catch (e) {
      return {};
    }
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    
    await for (final entity in source.list(recursive: false)) {
      if (entity is Directory) {
        final newDirectory = Directory(path.join(
          destination.path,
          path.basename(entity.path),
        ));
        await _copyDirectory(entity, newDirectory);
      } else if (entity is File) {
        final newFile = File(path.join(
          destination.path,
          path.basename(entity.path),
        ));
        await entity.copy(newFile.path);
      }
    }
  }

  Future<CharacterKeybinds?> getCharacterKeybinds(String characterId) async {
    try {
      if (modsPath == null) return null;
      final characterPath = path.join(modsPath!, characterId);
      if (!await Directory(characterPath).exists()) return null;
      return await _iniParser.parseCharacterDirectory(characterId, characterPath);
    } catch (e) {
      print('ModManagerService: getCharacterKeybinds error for $characterId: $e');
      return null;
    }
  }

  Future<Map<String, CharacterKeybinds>> getAllCharactersKeybinds() async {
    try {
      if (modsPath == null) return {};
      return await _iniParser.parseAllCharacters(modsPath!);
    } catch (e) {
      print('ModManagerService: getAllCharactersKeybinds error: $e');
      return {};
    }
  }

  Future<List<KeybindInfo>?> getModKeybinds(String modId) async {
    try {
      if (modsPath == null) return null;
      final modPath = path.join(modsPath!, modId);
      final keybindsData = await _iniParser.parseCharacterDirectory(modId, modPath);
      return keybindsData?.keybinds;
    } catch (e) {
      print('ModManagerService: getModKeybinds error for $modId: $e');
      return null;
    }
  }

  Future<List<CharacterInfo>> enrichCharactersWithKeybinds(
    List<CharacterInfo> characters,
  ) async {
    try {
      final updatedCharacters = <CharacterInfo>[];
      for (final character in characters) {
        final updatedMods = <ModInfo>[];
        for (final mod in character.skins) {
          final keybinds = await getModKeybinds(mod.id);
          if (keybinds != null && keybinds.isNotEmpty) {
            print('ModManagerService: found ${keybinds.length} keybinds for ${mod.id}');
            updatedMods.add(mod.copyWith(keybinds: keybinds));
          } else {
            updatedMods.add(mod);
          }
        }
        updatedCharacters.add(character.copyWith(skins: updatedMods));
      }
      return updatedCharacters;
    } catch (e) {
      print('ModManagerService: enrichCharactersWithKeybinds error: $e');
      return characters;
    }
  }
}
