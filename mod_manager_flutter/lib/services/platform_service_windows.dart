import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/path_helper.dart';
import 'platform_service.dart';

class WindowsPlatformService implements PlatformService {
  
  @override
  Future<bool> sendF10ToGame() async {
    print('WindowsPlatformService: sending f10...');
    
    try {
      final windowNames = [
        'Zenless Zone Zero',
        'ZenlessZoneZero',
        'Zenless',
        'ZZZ'
      ];
      
      int hwnd = 0;
      for (final name in windowNames) {
        final namePtr = name.toNativeUtf16();
        try {
          hwnd = FindWindow(nullptr, namePtr);
          if (hwnd != 0) {
            print('WindowsPlatformService: found game window: $name (HWND: $hwnd)');
            break;
          }
        } finally {
          calloc.free(namePtr);
        }
      }
      
      if (hwnd == 0) {
        print('WindowsPlatformService: game window not found');
        return await _sendF10ToForegroundWindow();
      }
      
      final isVisible = IsWindowVisible(hwnd);
      if (isVisible == FALSE) {
        print('WindowsPlatformService: game window not visible');
        return false;
      }
      
      SetForegroundWindow(hwnd);
      await Future.delayed(const Duration(milliseconds: 100));
      
      PostMessage(hwnd, WM_KEYDOWN, VK_F10, 0);
      await Future.delayed(const Duration(milliseconds: 50));
      PostMessage(hwnd, WM_KEYUP, VK_F10, 0);
      
      print('WindowsPlatformService: f10 sent');
      return true;
    } catch (e) {
      print('WindowsPlatformService: f10 send failed: $e');
      return false;
    }
  }
  
  @override
  Future<bool> createModLink(String sourcePath, String linkPath) async {
    try {
      print('WindowsPlatformService: creating link: $linkPath -> $sourcePath');
      
      if (await Directory(linkPath).exists() || await File(linkPath).exists()) {
        await removeModLink(linkPath);
      }
      
      try {
        final link = Link(linkPath);
        await link.create(sourcePath, recursive: false);
        print('WindowsPlatformService: symlink created');
        return true;
      } catch (e) {
        print('WindowsPlatformService: symlink creation failed: $e');
        print('WindowsPlatformService: trying junction...');
      }
      
      final result = await Process.run(
        'cmd',
        ['/c', 'mklink', '/J', linkPath, sourcePath],
        runInShell: true,
      );
      
      if (result.exitCode == 0) {
        print('WindowsPlatformService: junction created');
        return true;
      } else {
        print('WindowsPlatformService: junction creation failed: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('WindowsPlatformService: link creation failed: $e');
      return false;
    }
  }
  
  @override
  Future<bool> removeModLink(String linkPath) async {
    try {
      final isLink = await isModLink(linkPath);
      if (!isLink) {
        final dir = Directory(linkPath);
        if (await dir.exists()) {
          await dir.delete(recursive: false);
          print('WindowsPlatformService: directory deleted: $linkPath');
          return true;
        }
        return false;
      }
      
      final link = Link(linkPath);
      if (await link.exists()) {
        await link.delete();
        print('WindowsPlatformService: link deleted: $linkPath');
        return true;
      }
      
      return false;
    } catch (e) {
      print('WindowsPlatformService: link delete failed: $e');
      return false;
    }
  }
  
  @override
  Future<bool> isModLink(String linkPath) async {
    try {
      final isLink = await FileSystemEntity.isLink(linkPath);
      if (isLink) return true;
      
      return await _isJunction(linkPath);
    } catch (e) {
      return false;
    }
  }
  
  @override
  String getAppDataPath() => PathHelper.getAppDataPath();

  @override
  void showSetupInstructions() {
    print('\n═══════════════════════════════════════════════════════════');
    print('F10 Auto-Reload Setup Instructions (Windows)');
    print('═══════════════════════════════════════════════════════════\n');
    print('f10 auto-reload works via windows api');
    print('no extra tools needed\n');
    print('for symbolic links:');
    print('  option 1 (recommended): enable developer mode');
    print('    Settings → Update & Security → For developers');
    print('    → Developer Mode (ON)');
    print('\n  option 2: the app falls back to directory junctions');
    print('    (work without admin rights)\n');
    print('  option 3: run the app as administrator');
    print('    (right click -> run as administrator)');
    print('\n═══════════════════════════════════════════════════════════\n');
  }
  
  @override
  Future<bool> checkDependencies() async {
    print('WindowsPlatformService: checking dependencies...');
    
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd != 0) {
        print('WindowsPlatformService: windows api available');
        return true;
      }
    } catch (e) {
      print('WindowsPlatformService: windows api access failed: $e');
      return false;
    }
    
    print('WindowsPlatformService: all dependencies available');
    return true;
  }
  
  @override
  Future<List<String>> findGameProcesses() async {
    try {
      final result = await Process.run('tasklist', ['/FI', 'IMAGENAME eq ZenlessZoneZero.exe']);
      final processes = <String>[];
      
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.toLowerCase().contains('zenless') || 
              line.toLowerCase().contains('zzz')) {
            processes.add(line.trim());
          }
        }
      }
      
      print('WindowsPlatformService: found game processes: ${processes.length}');
      return processes;
    } catch (e) {
      print('WindowsPlatformService: process search failed: $e');
      return [];
    }
  }
  
  @override
  String getDisplayServerType() {
    return 'windows-dwm';
  }
  
  @override
  Future<bool> openUrlInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      final result = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (result) {
        print('WindowsPlatformService: browser opened: $url');
        return true;
      }
      
      print('WindowsPlatformService: could not open browser');
      return false;
    } catch (e) {
      print('WindowsPlatformService: browser open failed: $e');
      return false;
    }
  }
  
  @override
  String? getSystemDownloadsPath() {
    try {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) return null;
      
      return path.join(userProfile, 'Downloads');
    } catch (e) {
      print('WindowsPlatformService: could not resolve downloads dir: $e');
      return null;
    }
  }
  
  
  Future<bool> _sendF10ToForegroundWindow() async {
    try {
      final hwnd = GetForegroundWindow();
      if (hwnd == 0) {
        print('WindowsPlatformService: could not get active window');
        return false;
      }
      
      PostMessage(hwnd, WM_KEYDOWN, VK_F10, 0);
      await Future.delayed(const Duration(milliseconds: 50));
      PostMessage(hwnd, WM_KEYUP, VK_F10, 0);
      
      print('WindowsPlatformService: f10 sent to active window');
      return true;
    } catch (e) {
      print('WindowsPlatformService: error: $e');
      return false;
    }
  }
  
  Future<bool> _isJunction(String dirPath) async {
    try {
      final result = await Process.run(
        'cmd',
        ['/c', 'dir', '/AL', dirPath],
        runInShell: true,
      );
      
      return result.stdout.toString().contains('JUNCTION');
    } catch (e) {
      return false;
    }
  }
}
