import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

import '../core/app_version.dart';
import '../models/update_info.dart';

/// how this copy of the app was installed
enum InstallKind {
  /// unpacked zip the user owns, safe to replace in place
  portable,

  /// distro or system managed (aur, /usr, /opt, program files), update via the package manager
  managed,
}

class UpdateService {
  static const String repoSlug = 'hugobugomugo/Modlinq';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$repoSlug/releases/latest';

  final http.Client _client;

  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  // ---- pure helpers, covered by tests ----

  /// parses `1.2.3` / `v1.2.3-beta.1` into core numbers plus prerelease tail
  static (List<int>, String) parseVersion(String raw) {
    var v = raw.trim();
    if (v.startsWith('v')) v = v.substring(1);
    final dash = v.indexOf('-');
    final pre = dash == -1 ? '' : v.substring(dash + 1);
    final core = dash == -1 ? v : v.substring(0, dash);
    final parts = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (parts.length < 3) {
      parts.add(0);
    }
    return (parts.sublist(0, 3), pre);
  }

  /// true when [remote] is a strictly newer version than [current]
  static bool isNewer(String remote, String current) {
    final (rc, rp) = parseVersion(remote);
    final (cc, cp) = parseVersion(current);
    for (var i = 0; i < 3; i++) {
      if (rc[i] != cc[i]) return rc[i] > cc[i];
    }
    // same core: a release beats a prerelease, otherwise compare tails
    if (rp.isEmpty && cp.isNotEmpty) return true;
    if (rp.isNotEmpty && cp.isEmpty) return false;
    return comparePrerelease(rp, cp) > 0;
  }

  /// semver prerelease ordering: dot-separated identifiers, numeric ones
  /// compared as numbers so dev.10 outranks dev.9, numeric below alphanumeric,
  /// and a longer tail outranks a shorter identical prefix
  static int comparePrerelease(String a, String b) {
    if (a == b) return 0;
    final as = a.split('.');
    final bs = b.split('.');
    for (var i = 0; i < as.length && i < bs.length; i++) {
      final an = int.tryParse(as[i]);
      final bn = int.tryParse(bs[i]);
      if (an != null && bn != null) {
        if (an != bn) return an.compareTo(bn);
      } else if (an != null) {
        return -1;
      } else if (bn != null) {
        return 1;
      } else {
        final c = as[i].compareTo(bs[i]);
        if (c != 0) return c;
      }
    }
    return as.length.compareTo(bs.length);
  }

  /// release asset suffix for the running platform
  static String platformAssetSuffix() =>
      Platform.isWindows ? 'windows-x64.zip' : 'linux-x64.zip';

  /// pulls `<sha256>  <filename>` pairs out of a SHA256SUMS.txt body
  static Map<String, String> parseChecksums(String body) {
    final out = <String, String>{};
    for (final line in const LineSplitter().convert(body)) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final m = RegExp(r'^([a-fA-F0-9]{64})\s+\*?(.+)$').firstMatch(t);
      if (m != null) out[m.group(2)!.trim()] = m.group(1)!.toLowerCase();
    }
    return out;
  }

  static Directory installDir() => File(Platform.resolvedExecutable).parent;

  /// system paths we must never try to overwrite from inside the app
  static bool isSystemPath(String p) {
    final lower = p.replaceAll(r'\', '/').toLowerCase();
    final probe = lower.endsWith('/') ? lower : '$lower/';
    const roots = ['/usr/', '/opt/', '/bin/', '/sbin/', '/nix/store/'];
    for (final r in roots) {
      if (probe.startsWith(r)) return true;
    }
    return lower.contains('/program files');
  }

  /// managed installs cannot self update, the package manager owns the files
  static Future<InstallKind> detectInstallKind({Directory? dir}) async {
    final d = dir ?? installDir();
    if (isSystemPath(d.path)) return InstallKind.managed;
    // final say: can we actually write next to the binary
    try {
      final probe = File(path.join(d.path, '.modlinq-write-probe'));
      await probe.writeAsString('x', flush: true);
      await probe.delete();
      return InstallKind.portable;
    } catch (_) {
      return InstallKind.managed;
    }
  }

  // ---- network ----

  Future<UpdateInfo?> checkForUpdate({String current = appVersion}) async {
    final res = await _client.get(
      Uri.parse(latestReleaseUrl),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'modlinq-updater',
      },
    );
    if (res.statusCode != 200) return null;

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final tag = (json['tag_name'] ?? '') as String;
    if (tag.isEmpty) return null;

    final version = tag.startsWith('v') ? tag.substring(1) : tag;
    if (!isNewer(version, current)) return null;

    final assets = (json['assets'] as List?) ?? const [];
    final suffix = platformAssetSuffix();

    Map<String, dynamic>? asset;
    String? checksumUrl;
    for (final a in assets.cast<Map<String, dynamic>>()) {
      final name = (a['name'] ?? '') as String;
      if (name.endsWith(suffix)) asset = a;
      if (name == 'SHA256SUMS.txt') {
        checksumUrl = a['browser_download_url'] as String?;
      }
    }
    if (asset == null) return null;

    return UpdateInfo(
      version: version,
      tag: tag,
      notes: (json['body'] ?? '') as String,
      assetName: asset['name'] as String,
      assetUrl: asset['browser_download_url'] as String,
      assetSize: (asset['size'] ?? 0) as int,
      checksumUrl: checksumUrl,
    );
  }

  Future<File> downloadAsset(
    UpdateInfo info, {
    void Function(int received, int total)? onProgress,
  }) async {
    final dir = await Directory.systemTemp.createTemp('modlinq-update');
    final out = File(path.join(dir.path, info.assetName));

    final req = http.Request('GET', Uri.parse(info.assetUrl));
    req.headers['User-Agent'] = 'modlinq-updater';
    final res = await _client.send(req);
    if (res.statusCode != 200) {
      throw HttpException('download failed: ${res.statusCode}');
    }

    final total = res.contentLength ?? info.assetSize;
    var received = 0;
    final sink = out.openWrite();
    await for (final chunk in res.stream) {
      received += chunk.length;
      sink.add(chunk);
      onProgress?.call(received, total);
    }
    await sink.close();
    return out;
  }

  Future<bool> verifyChecksum(File file, String expectedSha256) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString().toLowerCase() == expectedSha256.toLowerCase();
  }

  Future<String?> fetchExpectedChecksum(UpdateInfo info) async {
    // release body carries the sums as text, asset file is the fallback
    final fromNotes = parseChecksums(info.notes)[info.assetName];
    if (fromNotes != null) return fromNotes;
    if (info.checksumUrl == null) return null;
    final res = await _client.get(
      Uri.parse(info.checksumUrl!),
      headers: const {'User-Agent': 'modlinq-updater'},
    );
    if (res.statusCode != 200) return null;
    return parseChecksums(res.body)[info.assetName];
  }

  /// unpacks the zip into a staging dir next to the install and returns it
  Future<Directory> stageUpdate(File zip, {Directory? target}) async {
    final install = target ?? installDir();
    final staging = Directory(path.join(install.parent.path, '.modlinq-staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    await extractFileToDisk(zip.path, staging.path);
    return staging;
  }

  /// the running binary cannot overwrite itself, so the swap is handed to a
  /// detached helper that waits for this pid to exit first
  static String buildSwapScript({
    required int processId,
    required String stagingPath,
    required String installPath,
    required String exeName,
  }) {
    if (Platform.isWindows) {
      return '''
@echo off
:wait
tasklist /FI "PID eq $processId" 2>nul | find "$processId" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto wait
)
xcopy /E /Y /I "$stagingPath\\*" "$installPath\\" >nul
rmdir /S /Q "$stagingPath"
start "" "$installPath\\$exeName"
del "%~f0"
''';
    }
    return '''
#!/bin/sh
while kill -0 $processId 2>/dev/null; do sleep 0.2; done
cp -a "$stagingPath/." "$installPath/"
rm -rf "$stagingPath"
chmod +x "$installPath/$exeName"
"$installPath/$exeName" &
rm -- "\$0"
''';
  }

  /// spawns the swap helper and returns, the caller then exits the app
  Future<void> applyUpdate(Directory staging, {Directory? target}) async {
    final install = target ?? installDir();
    final exeName = path.basename(Platform.resolvedExecutable);
    final ext = Platform.isWindows ? 'bat' : 'sh';
    final script = File(path.join(staging.parent.path, 'modlinq-swap.$ext'));

    await script.writeAsString(buildSwapScript(
      processId: pid,
      stagingPath: staging.path,
      installPath: install.path,
      exeName: exeName,
    ));

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', script.path]);
      await Process.start('/bin/sh', [script.path],
          mode: ProcessStartMode.detached);
    } else {
      await Process.start('cmd', ['/c', 'start', '/b', script.path],
          mode: ProcessStartMode.detached);
    }
  }
}
