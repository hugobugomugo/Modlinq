import 'package:flutter/foundation.dart';

import 'gamebanana_client.dart';

enum MarketplaceJobStatus { queued, running, done, failed }

/// One marketplace download, from click to installed mod.
@immutable
class MarketplaceJob {
  final GameBananaMod mod;

  /// The archive to install. Picked before queueing, so a file GameBanana
  /// flagged is confirmed while the user is still looking at the card.
  final GameBananaFile file;

  /// Game key the mod is being installed for. A job started for one game must
  /// not be reported as installed for another.
  final String gameKey;

  final MarketplaceJobStatus status;

  /// 0..1 while downloading, null when the size is unknown.
  final double? progress;

  final String? error;

  /// Name the mod ended up with in the library, once installed.
  final String? installedAs;

  const MarketplaceJob({
    required this.mod,
    required this.file,
    required this.gameKey,
    this.status = MarketplaceJobStatus.queued,
    this.progress,
    this.error,
    this.installedAs,
  });

  bool get isFinished =>
      status == MarketplaceJobStatus.done ||
      status == MarketplaceJobStatus.failed;

  MarketplaceJob copyWith({
    MarketplaceJobStatus? status,
    double? progress,
    String? error,
    String? installedAs,
  }) => MarketplaceJob(
    mod: mod,
    file: file,
    gameKey: gameKey,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    error: error ?? this.error,
    installedAs: installedAs ?? this.installedAs,
  );
}

/// Does the actual work for one job and returns the installed mod's name.
typedef MarketplaceWorker =
    Future<String> Function(
      MarketplaceJob job,
      void Function(double progress) onProgress,
    );

/// Runs marketplace installs one after another.
///
/// Clicking install on a second mod while the first is still downloading used
/// to be impossible; now it queues. Sequential on purpose: parallel downloads
/// of 200 MB archives fight for bandwidth and the unpack step is disk bound
/// anyway.
class MarketplaceQueue extends ValueNotifier<List<MarketplaceJob>> {
  final MarketplaceWorker worker;

  bool _isProcessing = false;

  MarketplaceQueue({required this.worker}) : super(const []);

  /// Jobs that are queued or running, oldest first.
  List<MarketplaceJob> get pending =>
      value.where((job) => !job.isFinished).toList();

  MarketplaceJob? jobFor(int modId, String gameKey) {
    for (final job in value) {
      if (job.mod.id == modId && job.gameKey == gameKey) return job;
    }
    return null;
  }

  /// Adds a job unless the same mod is already queued or running.
  bool enqueue(GameBananaMod mod, GameBananaFile file, String gameKey) {
    final existing = jobFor(mod.id, gameKey);
    if (existing != null && !existing.isFinished) return false;

    value = [
      ...value.where((job) => !(job.mod.id == mod.id && job.gameKey == gameKey)),
      MarketplaceJob(mod: mod, file: file, gameKey: gameKey),
    ];

    _drain();
    return true;
  }

  /// Forgets finished jobs, so the list does not grow for a whole session.
  void clearFinished() =>
      value = value.where((job) => !job.isFinished).toList();

  Future<void> _drain() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        final next = value.firstWhere(
          (job) => job.status == MarketplaceJobStatus.queued,
          orElse: () => _noJob,
        );
        if (identical(next, _noJob)) break;

        await _run(next);
      }
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _run(MarketplaceJob job) async {
    _update(job, job.copyWith(status: MarketplaceJobStatus.running));

    try {
      final name = await worker(job, (progress) {
        final current = jobFor(job.mod.id, job.gameKey);
        if (current == null) return;
        _update(current, current.copyWith(progress: progress));
      });

      final current = jobFor(job.mod.id, job.gameKey) ?? job;
      _update(
        current,
        current.copyWith(status: MarketplaceJobStatus.done, installedAs: name),
      );
    } catch (e) {
      final current = jobFor(job.mod.id, job.gameKey) ?? job;
      _update(
        current,
        current.copyWith(status: MarketplaceJobStatus.failed, error: '$e'),
      );
    }
  }

  void _update(MarketplaceJob previous, MarketplaceJob next) {
    value = [
      for (final job in value)
        if (job.mod.id == previous.mod.id && job.gameKey == previous.gameKey)
          next
        else
          job,
    ];
  }

  static const MarketplaceJob _noJob = MarketplaceJob(
    mod: GameBananaMod(
      id: -1,
      name: '',
      author: '',
      profileUrl: '',
      hasFiles: false,
    ),
    file: GameBananaFile(name: '', size: 0, downloadUrl: ''),
    gameKey: '',
  );
}
