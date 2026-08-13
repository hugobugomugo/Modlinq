import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/nte_game_detection.dart';
import '../../utils/state_providers.dart';

/// Setup and status view for Neverness to Everness.
///
/// Slice 1 of the NTE integration: locates the install and stores its path.
/// Mod management for NTE is not wired up yet.
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

    // Detection walks Steam libraries, so keep it off the UI thread.
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
              else if (install != null && install.valid)
                _buildDetected(install, isDarkMode, loc)
              else
                _buildNotFound(loc),
              const SizedBox(height: 24),
              Text(
                loc.t('nte.setup.mods_coming_soon'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetected(NteInstall install, bool isDarkMode, AppLocalizations loc) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                loc.t('nte.setup.detected'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildRow(loc.t('nte.setup.path'), install.path),
          _buildRow(loc.t('nte.setup.edition'), install.edition.key.toUpperCase()),
          if (install.protonPrefix != null)
            _buildRow(loc.t('nte.setup.proton_prefix'), install.protonPrefix!),
          _buildRow(
            loc.t('nte.setup.mods_folder'),
            Directory(install.paksModsPath).existsSync()
                ? install.paksModsPath
                : '${install.paksModsPath} (${loc.t('nte.setup.will_be_created')})',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open, size: 16),
              label: Text(loc.t('nte.setup.change_folder')),
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

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
