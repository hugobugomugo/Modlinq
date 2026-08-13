import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nte_mod.dart';
import '../../services/api_service.dart';
import '../../services/nte_mod_manager.dart';
import '../../utils/state_providers.dart';

/// Mod library view for Neverness to Everness.
///
/// Toggling a mod applies the change immediately. Mods the game holds open are
/// reported as pending and retried on the next refresh.
class NteModsList extends ConsumerStatefulWidget {
  final String gamePath;

  const NteModsList({super.key, required this.gamePath});

  @override
  ConsumerState<NteModsList> createState() => _NteModsListState();
}

class _NteModsListState extends ConsumerState<NteModsList> {
  NteModManager? _manager;
  List<NteMod> _mods = const [];
  Set<String> _pending = {};
  bool _isLoading = true;
  bool _isDragging = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ApiService.getConfigService();
    final manager = NteModManager.fromConfig(config);

    if (manager == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    manager.library.ensureExists();

    // Retry anything the game had locked when it was last toggled.
    final sync = manager.syncWithIntent();

    if (!mounted) return;
    setState(() {
      _manager = manager;
      _mods = manager.listMods();
      _pending = sync.locked.toSet();
      _isLoading = false;
    });
  }

  Future<void> _toggle(NteMod mod) async {
    final manager = _manager;
    if (manager == null) return;

    final result = await manager.setEnabled(mod.name, !mod.enabled);

    if (!mounted) return;
    setState(() {
      _mods = manager.listMods();
      _pending = {..._pending}..removeWhere((name) => name == mod.name);
      if (result.locked.contains(mod.name)) _pending.add(mod.name);
    });

    if (result.locked.isNotEmpty) {
      _showMessage(context.loc.t('nte.mods.locked'), isError: true);
    }
    for (final error in result.errors.values) {
      _showMessage(error, isError: true);
    }
  }

  Future<void> _import(List<String> paths) async {
    final manager = _manager;
    if (manager == null || paths.isEmpty) return;

    final skipped = <String, String>{};
    final imported = manager.import(paths, skipped: skipped);

    if (!mounted) return;
    setState(() => _mods = manager.listMods());

    if (imported.isNotEmpty) {
      _showMessage(
        context.loc.t('nte.mods.imported', params: {'count': '${imported.length}'}),
      );
    }
    for (final entry in skipped.entries) {
      _showMessage('${entry.key}: ${entry.value}', isError: true);
    }
  }

  Future<void> _pickAndImport() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final paths = result?.files.map((f) => f.path).whereType<String>().toList();
    if (paths != null) await _import(paths);
  }

  Future<void> _pickFolderAndImport() async {
    final picked = await FilePicker.getDirectoryPath();
    if (picked != null) await _import([picked]);
  }

  Future<void> _delete(NteMod mod) async {
    final manager = _manager;
    if (manager == null) return;

    final confirmed = await _confirmDelete(mod.name);
    if (confirmed != true) return;

    await manager.delete(mod.name);
    if (mounted) setState(() => _mods = manager.listMods());
  }

  Future<bool?> _confirmDelete(String modName) {
    final loc = context.loc;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.t('nte.mods.delete_title')),
        content: Text(loc.t('nte.mods.delete_message', params: {'mod': modName})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.t('mods.dialog.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.t('nte.mods.delete_confirm')),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.loc;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final query = _query.trim().toLowerCase();
    final visible = query.isEmpty
        ? _mods
        : _mods.where((m) => m.name.toLowerCase().contains(query)).toList();

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        _import(details.files.map((f) => f.path).toList());
      },
      child: Container(
        decoration: _isDragging
            ? BoxDecoration(
                border: Border.all(color: const Color(0xFF0EA5E9), width: 2),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Column(
          children: [
            _buildToolbar(loc),
            Expanded(
              child: visible.isEmpty
                  ? _buildEmptyState(loc)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: visible.length,
                      itemBuilder: (context, index) => _buildModTile(visible[index], loc),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(AppLocalizations loc) {
    final enabledCount = _mods.where((m) => m.enabled).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: loc.t('nte.mods.search'),
                prefixIcon: const Icon(Icons.search, size: 16),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            loc.t(
              'nte.mods.count',
              params: {'enabled': '$enabledCount', 'total': '${_mods.length}'},
            ),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const Spacer(),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: loc.t('mods.actions.refresh'),
          ),
          OutlinedButton.icon(
            onPressed: _pickFolderAndImport,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(loc.t('nte.mods.import_folder')),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _pickAndImport,
            icon: const Icon(Icons.archive, size: 16),
            label: Text(loc.t('nte.mods.import_zip')),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations loc) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.extension_off, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          Text(
            loc.t(_mods.isEmpty ? 'nte.mods.empty' : 'nte.mods.no_matches'),
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildModTile(NteMod mod, AppLocalizations loc) {
    final isPending = _pending.contains(mod.name);
    final isDarkMode = ref.watch(isDarkModeProvider);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: isDarkMode ? Colors.white.withValues(alpha: 0.04) : null,
      child: ListTile(
        leading: Switch(
          value: mod.enabled,
          onChanged: mod.isInstallable ? (_) => _toggle(mod) : null,
        ),
        title: Text(mod.name, style: const TextStyle(fontSize: 14)),
        subtitle: Row(
          children: [
            _buildTag(mod.isPak ? 'PAK' : 'ASI'),
            if (mod.category != null) ...[
              const SizedBox(width: 6),
              _buildTag(mod.category!),
            ],
            if (!mod.isInstallable) ...[
              const SizedBox(width: 6),
              Text(
                loc.t('nte.mods.not_installable'),
                style: const TextStyle(fontSize: 11, color: Color(0xFFDC2626)),
              ),
            ],
            if (isPending) ...[
              const SizedBox(width: 6),
              Text(
                loc.t('nte.mods.pending'),
                style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          onPressed: () => _delete(mod),
          icon: const Icon(Icons.delete_outline, size: 18),
          tooltip: loc.t('nte.mods.delete_title'),
        ),
      ),
    );
  }

  Widget _buildTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Color(0xFF0EA5E9)),
      ),
    );
  }
}
