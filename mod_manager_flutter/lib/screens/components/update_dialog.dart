import 'dart:io';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/update_info.dart';
import '../../services/update_service.dart';

enum _Stage { prompt, downloading, verifying, applying, failed }

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  final UpdateService service;

  const UpdateDialog({super.key, required this.info, required this.service});

  /// checks in the background and only shows a dialog when something is there
  static Future<void> maybeShow(
    BuildContext context, {
    UpdateService? service,
  }) async {
    final svc = service ?? UpdateService();
    if (await UpdateService.detectInstallKind() == InstallKind.managed) return;

    UpdateInfo? info;
    try {
      info = await svc.checkForUpdate();
    } catch (_) {
      return;
    }
    if (info == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => UpdateDialog(info: info!, service: svc),
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
    try {
      setState(() => _stage = _Stage.downloading);
      final zip = await svc.downloadAsset(
        info,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() => _progress = received / total);
        },
      );

      setState(() => _stage = _Stage.verifying);
      final expected = await svc.fetchExpectedChecksum(info);
      if (expected != null && !await svc.verifyChecksum(zip, expected)) {
        setState(() {
          _stage = _Stage.failed;
          _error = 'checksum mismatch, update aborted';
        });
        return;
      }

      setState(() => _stage = _Stage.applying);
      final staging = await svc.stageUpdate(zip);
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
