import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/nte_game_detection.dart';
import 'nte_mods_list.dart';
import '../../utils/state_providers.dart';

/// Entry point for the Neverness to Everness tab.
///
/// Locates the install, then hands over to the mod library. Until a valid
/// game folder is known it shows detection and a manual folder picker.
class NteSetupPanel extends ConsumerStatefulWidget {
  const NteSetupPanel({super.key});

  @override
  ConsumerState<NteSetupPanel> createState() => _NteSetupPanelState();
}

class _NteSetupPanelState extends ConsumerState<NteSetupPanel> {
  NteInstall? _install;
  bool _isDetecting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedOrDetect();
  }

  Future<void> _loadSavedOrDetect() async {
    final configService = await ApiService.getConfigService();
    final savedPath = configService.nteGamePath;

    if (savedPath != null && savedPath.isNotEmpty) {
      final check = NteGameDetection.validate(savedPath);
      if (check.valid) {
        if (mounted) setState(() => _install = check);
        return;
      }
    }

    await _detect();
  }

  Future<void> _detect() async {
    setState(() => _isDetecting = true);

    // Detection walks Steam libraries and Wine prefixes off the UI thread.
    final result = await Future(() => NteGameDetection.autoDetect());

    if (result.valid) await _persist(result.path);
    if (mounted) {
      setState(() {
        _install = result;
        _isDetecting = false;
      });
    }
  }

  Future<void> _pickFolder() async {
    final picked = await FilePicker.getDirectoryPath();
    if (picked == null) return;

    final check = NteGameDetection.validate(picked);
    if (check.valid) {
      await _persist(check.path);
      if (mounted) setState(() => _install = check);
      return;
    }

    if (mounted) {
      setState(() => _install = check);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.loc.t('nte.setup.invalid_folder')),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _persist(String gamePath) async {
    final configService = await ApiService.getConfigService();
    await configService.setNteGamePath(gamePath);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;
    final isDarkMode = ref.watch(isDarkModeProvider);
    final install = _install;

    // Once the game is located, the panel gets out of the way and the library
    // takes over; the install details stay reachable from the header.
    if (install != null && install.valid) {
      return Column(
        children: [
          _buildInstallHeader(install, isDarkMode, loc),
          Expanded(child: NteModsList(gamePath: install.path)),
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                GameType.nte.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 24),
              if (_isDetecting)
                const Center(child: CircularProgressIndicator())
              else
                _buildNotFound(loc),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact status bar shown above the mod library.
  Widget _buildInstallHeader(NteInstall install, bool isDarkMode, AppLocalizations loc) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.03),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 8),
          Text(
            '${GameType.nte.displayName} · ${install.edition.key.toUpperCase()}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Tooltip(
              message: install.path,
              child: Text(
                install.path,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _pickFolder,
            icon: const Icon(Icons.folder_open, size: 14),
            label: Text(
              loc.t('nte.setup.change_folder'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound(AppLocalizations loc) {
    return Column(
      children: [
        const Icon(Icons.search_off, size: 40, color: Colors.grey),
        const SizedBox(height: 12),
        Text(
          loc.t('nte.setup.not_found'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _detect,
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(loc.t('nte.setup.detect_again')),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(loc.t('nte.setup.select_folder')),
            ),
          ],
        ),
      ],
    );
  }
}
