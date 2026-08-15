import 'dart:io';
import 'package:path/path.dart' as path;

class F10ReloadService {
  
  Future<List<String>> _findGameProcesses() async {
    try {
      final result = await Process.run('ps', ['aux']);
      final processes = <String>[];
      
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        for (final line in lines) {
          if (line.toLowerCase().contains('zenless') || 
              line.toLowerCase().contains('zzz') ||
              line.contains('ZenlessZoneZero.exe')) {
            processes.add(line.trim());
          }
        }
      }
      
      print('F10ReloadService: found game processes: ${processes.length}');
      return processes;
    } catch (e) {
      print('F10ReloadService: process search failed: $e');
      return [];
    }
  }

  Future<bool> _sendF10ViaXdotool() async {
    try {
      final checkResult = await Process.run('which', ['xdotool']);
      if (checkResult.exitCode != 0) {
        print('F10ReloadService: xdotool not installed');
        return false;
      }

      String? windowId;
      final windowNames = ['Zenless', 'ZZZ', 'zenless'];
      
      for (final name in windowNames) {
        try {
          final windowResult = await Process.run('xdotool', [
            'search', '--name', '--onlyvisible', name
          ]);
          
          if (windowResult.exitCode == 0 && windowResult.stdout.toString().trim().isNotEmpty) {
            windowId = windowResult.stdout.toString().trim().split('\n').first;
            print('F10ReloadService: found game window: $name (ID: $windowId)');
            break;
          }
        } catch (e) {
          continue;
        }
      }

      if (windowId == null) {
        print('F10ReloadService: game window not found via xdotool');
        await Process.run('xdotool', ['key', 'F10']);
        return true;
      }

      await Process.run('xdotool', ['windowactivate', windowId]);
      await Future.delayed(const Duration(milliseconds: 200));

      final keyResult = await Process.run('xdotool', [
        'key', '--window', windowId, 'F10'
      ]);

      if (keyResult.exitCode == 0) {
        print('F10ReloadService: f10 sent via xdotool');
        return true;
      } else {
        print('F10ReloadService: f10 send via xdotool failed');
        return false;
      }
    } catch (e) {
      print('F10ReloadService: xdotool error: $e');
      return false;
    }
  }

  Future<void> _focusGameWindow() async {
    try {
      final wmctrlCheck = await Process.run('which', ['wmctrl']);
      if (wmctrlCheck.exitCode == 0) {
        final windowNames = ['Zenless', 'ZZZ', 'zenless'];
        for (final name in windowNames) {
          try {
            await Process.run('wmctrl', ['-a', name]);
            print('F10ReloadService: window activated via wmctrl: $name');
            return;
          } catch (e) {
            continue;
          }
        }
      }

      final xdotoolCheck = await Process.run('which', ['xdotool']);
      if (xdotoolCheck.exitCode == 0) {
        final windowNames = ['Zenless', 'ZZZ', 'zenless'];
        for (final name in windowNames) {
          try {
            final result = await Process.run('xdotool', [
              'search', '--name', name
            ]);
            
            if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
              final windowId = result.stdout.toString().trim().split('\n').first;
              await Process.run('xdotool', ['windowactivate', windowId]);
              print('F10ReloadService: window activated via xdotool: $name');
              return;
            }
          } catch (e) {
            continue;
          }
        }
      }
    } catch (e) {
      print('F10ReloadService: could not activate game window: $e');
    }
  }

  Future<bool> _sendF10ViaYdotool() async {
    try {
      final checkResult = await Process.run('which', ['ydotool']);
      if (checkResult.exitCode != 0) {
        print('F10ReloadService: ydotool not installed');
        return false;
      }

      await _focusGameWindow();
      
      await Future.delayed(const Duration(milliseconds: 200));

      for (int i = 0; i < 2; i++) {
        final keyResult = await Process.run('ydotool', [
          'key', '67:1', '67:0'
        ]);
        
        if (keyResult.exitCode != 0) {
          print('F10ReloadService: f10 send via ydotool failed (attempt ${i + 1})');
        }
        
        if (i < 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      print('F10ReloadService: f10 sent via ydotool');
      return true;
    } catch (e) {
      print('F10ReloadService: ydotool error: $e');
      return false;
    }
  }

  Future<bool> _createReloadSignalFile(String modsPath) async {
    try {
      final signalPath = path.join(modsPath, '.reload_signal');
      final timestampPath = path.join(modsPath, '.mod_timestamp');
      
      final signalFile = File(signalPath);
      await signalFile.writeAsString(DateTime.now().millisecondsSinceEpoch.toString());
      
      final timestampFile = File(timestampPath);
      await timestampFile.writeAsString(DateTime.now().millisecondsSinceEpoch.toString());
      
      print('F10ReloadService: signal files created');
      return true;
    } catch (e) {
      print('F10ReloadService: signal file creation failed: $e');
      return false;
    }
  }

  Future<bool> _createReloadIniFile(String modsPath) async {
    try {
      final iniPath = path.join(modsPath, 'mod_reload_trigger.ini');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      final iniContent = '''
; auto-generated file for mod reload
; created: ${DateTime.now().toIso8601String()}

[Constants]
; mod reload trigger
\$mod_reload_timestamp = $timestamp
\$force_reload = 1

[Present]
; reload config on next frame
post run = CommandListForceReload

[CommandListForceReload]
; force reload of config and mods
if \$force_reload == 1
    ; reset trigger
    \$force_reload = 0
    ; reload config (f10 equivalent)
    run = BuiltInCommandListReloadConfig
endif

; this file is deleted after a few seconds
; (done externally, 3dmigoto cannot delete files)
''';

      final file = File(iniPath);
      await file.writeAsString(iniContent);
      
      print('F10ReloadService: ini file created: $iniPath');
      
      Future.delayed(const Duration(seconds: 10), () async {
        try {
          if (await file.exists()) {
            await file.delete();
            print('F10ReloadService: temp ini file deleted');
          }
        } catch (e) {
          print('F10ReloadService: ini file delete failed: $e');
        }
      });
      
      return true;
    } catch (e) {
      print('F10ReloadService: ini file creation failed: $e');
      return false;
    }
  }

  Future<bool> _restartWineProcess() async {
    try {
      final processes = await _findGameProcesses();
      if (processes.isEmpty) {
        print('F10ReloadService: wine game processes not found');
        return false;
      }

      for (final processLine in processes) {
        final parts = processLine.split(RegExp(r'\s+'));
        if (parts.length > 1) {
          final pid = parts[1];
          try {
            await Process.run('kill', ['-USR1', pid]);
            print('F10ReloadService: sent sigusr1 to pid $pid');
          } catch (e) {
            print('F10ReloadService: signal send failed to $pid: $e');
          }
        }
      }
      
      return true;
    } catch (e) {
      print('F10ReloadService: wine process restart failed: $e');
      return false;
    }
  }

  String _getDisplayServer() {
    final sessionType = Platform.environment['XDG_SESSION_TYPE'];
    final waylandDisplay = Platform.environment['WAYLAND_DISPLAY'];
    final display = Platform.environment['DISPLAY'];
    
    if (sessionType == 'wayland' || waylandDisplay != null) {
      return 'wayland';
    } else if (display != null) {
      return 'x11';
    }
    
    return 'unknown';
  }

  Future<bool> _callPythonScript(String modsPath) async {
    try {
      final scriptPath = path.join(
        Directory.current.path, 
        'scripts', 
        'f10_reload.py'
      );
      
      final scriptFile = File(scriptPath);
      if (!await scriptFile.exists()) {
        print('F10ReloadService: python script not found: $scriptPath');
        return false;
      }

      final result = await Process.run('python3', [scriptPath, modsPath]);
      
      if (result.exitCode == 0) {
        print('F10ReloadService: python script ok');
        return true;
      } else {
        print('F10ReloadService: python script failed: ${result.stderr}');
        return false;
      }
    } catch (e) {
      print('F10ReloadService: python script execution failed: $e');
      return false;
    }
  }

  Future<bool> reloadMods(String? modsPath) async {
    if (modsPath == null || modsPath.isEmpty) {
      print('F10ReloadService: mods path not set');
      return false;
    }

    print('F10ReloadService: starting mod reload on linux...');
    print('F10ReloadService: mods path: $modsPath');
    
    final displayServer = _getDisplayServer();
    print('F10ReloadService: display server: $displayServer');

    bool success = false;

    if (await _createReloadSignalFile(modsPath)) {
      success = true;
    }

    if (await _createReloadIniFile(modsPath)) {
      success = true;
    }

    if (displayServer == 'x11') {
      if (await _sendF10ViaXdotool()) {
        success = true;
      }
    } else if (displayServer == 'wayland') {
      if (await _sendF10ViaYdotool()) {
        success = true;
      }
    }

    if (!success) {
      if (await _sendF10ViaXdotool() || await _sendF10ViaYdotool()) {
        success = true;
      }
    }

    if (!success) {
      print('F10ReloadService: falling back to python script...');
      if (await _callPythonScript(modsPath)) {
        success = true;
      }
    }

    if (success) {
      print('F10ReloadService: mod reload commands sent');
    } else {
      print('F10ReloadService: could not send reload commands');
    }

    return success;
  }

  Future<void> installDependencies() async {
    print('F10ReloadService: checking dependencies...');
    
    final displayServer = _getDisplayServer();
    
    if (displayServer == 'x11') {
      final result = await Process.run('which', ['xdotool']);
      if (result.exitCode != 0) {
        print('F10ReloadService: recommended: install xdotool:');
        print('  Ubuntu/Debian: sudo apt install xdotool');
        print('  Arch: sudo pacman -S xdotool');
        print('  Fedora: sudo dnf install xdotool');
      } else {
        print('F10ReloadService: xdotool installed');
      }
    } else if (displayServer == 'wayland') {
      final result = await Process.run('which', ['ydotool']);
      if (result.exitCode != 0) {
        print('F10ReloadService: recommended: install ydotool:');
        print('  Ubuntu/Debian: sudo apt install ydotool');
        print('  Arch: yay -S ydotool');
        print('  Fedora: sudo dnf install ydotool');
      } else {
        print('F10ReloadService: ydotool installed');
      }
    }
  }

  void showSetupInstructions() {
    print('F10ReloadService: setup instructions:');
    print('');
    print('1. make sure 3dmigoto/xxmi is configured correctly');
    print('2. d3dx.ini needs the line: reload_fixes = no_modifiers VK_F10');
    print('3. install the matching tools:');
    print('   - x11: xdotool');
    print('   - wayland: ydotool + wmctrl (recommended)');
    print('4. on wayland make sure ydotool has permissions:');
    print('   sudo usermod -a -G input \$USER');
    print('   sudo systemctl enable --now ydotool.service');
    print('5. launch the game via wine/proton/xxmi launcher');
    print('6. use this service for automatic mod reload');
    print('');
    print('important: game window must be visible (not minimized) for ydotool');
    print('');
  }
}