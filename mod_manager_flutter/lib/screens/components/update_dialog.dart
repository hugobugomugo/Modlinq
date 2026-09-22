import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/update_info.dart';
import '../../services/update_service.dart';

enum _Stage { prompt, downloading, verifying, applying, failed }

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService service;

  /// Decides how the update is applied: a portable copy swaps its own files,
  /// an installed copy re-runs the installer so shortcuts and the uninstall
  /// entry survive.
  final InstallKind installKind;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.service,
    this.installKind = InstallKind.portable,
  });

  /// Checks in the background and only shows a dialog when something is there.
  ///
  /// Returns the result so the caller can keep it around — the sidebar badge
  /// and the settings page show the same state without checking again.
  static Future<UpdateCheckResult> maybeShow(
    BuildContext context, {
    UpdateService? service,
    bool testChannel = false,
  }) async {
    final svc = service ?? UpdateService();
    final result = await svc.check(includePrereleases: testChannel);

    if (!result.hasUpdate || !context.mounted) return result;

    await show(context, result, service: svc);
    return result;
  }

  /// Opens the dialog for an already known update.
  static Future<void> show(
    BuildContext context,
    UpdateCheckResult result, {
    UpdateService? service,
  }) async {
    final info = result.info;
    if (info == null) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(
        info: info,
        service: service ?? UpdateService(),
        installKind: result.kind,
      ),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  _Stage _stage = _Stage.prompt;
  double _progress = 0;
  String _error = '';

  Future<void> _run() async {
    final svc = widget.service;
    final info = widget.info;
    final viaInstaller = widget.installKind == InstallKind.installed;

    try {
      setState(() => _stage = _Stage.downloading);
      void onProgress(int received, int total) {
        if (!mounted || total <= 0) return;
        setState(() => _progress = received / total);
      }

      final file = viaInstaller
          ? await svc.downloadInstaller(info, onProgress: onProgress)
          : await svc.downloadAsset(info, onProgress: onProgress);

      setState(() => _stage = _Stage.verifying);
      final expected = await svc.fetchExpectedChecksum(
        info,
        fileName: viaInstaller ? info.installerName : null,
      );
      if (expected != null && !await svc.verifyChecksum(file, expected)) {
        setState(() {
          _stage = _Stage.failed;
          _error = 'checksum mismatch, update aborted';
        });
        return;
      }

      setState(() => _stage = _Stage.applying);
      if (viaInstaller) {
        await svc.runInstaller(file);
        exit(0);
      }

      final staging = await svc.stageUpdate(file);
      await svc.applyUpdate(staging);
      exit(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final busy = _stage == _Stage.downloading ||
        _stage == _Stage.verifying ||
        _stage == _Stage.applying;

    return AlertDialog(
      title: Text(
        loc.t('update.available',
            params: {'version': widget.info.version},
            fallback: 'Update available: ${widget.info.version}'),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_stage == _Stage.prompt) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Text(
                    widget.info.notes.isEmpty
                        ? loc.t('update.no_notes', fallback: 'No release notes.')
                        : widget.info.notes,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.info.assetName}  '
                '(${(widget.info.assetSize / 1048576).toStringAsFixed(1)} MB)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (busy) ...[
              Text(switch (_stage) {
                _Stage.downloading =>
                  loc.t('update.downloading', fallback: 'Downloading...'),
                _Stage.verifying =>
                  loc.t('update.verifying', fallback: 'Verifying checksum...'),
                _ => loc.t('update.applying',
                    fallback: 'Applying update, the app will restart...'),
              }),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _stage == _Stage.downloading ? _progress : null,
              ),
            ],
            if (_stage == _Stage.failed)
              Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        if (_stage == _Stage.prompt) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.t('update.later', fallback: 'Later')),
          ),
          FilledButton(
            onPressed: _run,
            child: Text(loc.t('update.install', fallback: 'Update now')),
          ),
        ],
        if (_stage == _Stage.failed)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(loc.t('common.close', fallback: 'Close')),
          ),
      ],
    );
  }
}
