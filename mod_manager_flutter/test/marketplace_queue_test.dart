import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/utils/state_providers.dart';

import 'package:modlinq/services/gamebanana_client.dart';
import 'package:modlinq/services/marketplace_queue.dart';

const _file = GameBananaFile(
  name: 'skin.zip',
  size: 10,
  downloadUrl: 'https://gamebanana.com/dl/1',
);

GameBananaMod _mod(int id) => GameBananaMod(
  id: id,
  name: 'Mod $id',
  author: 'someone',
  profileUrl: 'https://gamebanana.com/mods/$id',
  hasFiles: true,
);

void main() {
  test('a single job runs and reports the installed name', () async {
    final queue = MarketplaceQueue(worker: (job, _) async => 'Installed ${job.mod.id}');

    queue.enqueue(_mod(1), _file, 'zzz');
    await pumpEventQueue();

    expect(queue.value.single.status, MarketplaceJobStatus.done);
    expect(queue.value.single.installedAs, 'Installed 1');
  });

  test('jobs run one at a time, in the order they were added', () async {
    final running = <int>[];
    var concurrent = 0;
    var maxConcurrent = 0;

    final queue = MarketplaceQueue(
      worker: (job, _) async {
        concurrent++;
        maxConcurrent = concurrent > maxConcurrent ? concurrent : maxConcurrent;
        // A real await gap is enough to expose overlap; a timed delay would
        // just make the test slow.
        await Future<void>.delayed(Duration.zero);
        running.add(job.mod.id);
        concurrent--;
        return 'ok';
      },
    );

    queue.enqueue(_mod(1), _file, 'zzz');
    queue.enqueue(_mod(2), _file, 'zzz');
    queue.enqueue(_mod(3), _file, 'zzz');
    await pumpEventQueue(times: 50);

    expect(running, [1, 2, 3]);
    expect(maxConcurrent, 1);
  });

  test('a queued mod does not block the ones behind it when it fails', () async {
    final done = <int>[];

    final queue = MarketplaceQueue(
      worker: (job, _) async {
        if (job.mod.id == 1) throw StateError('download failed');
        done.add(job.mod.id);
        return 'ok';
      },
    );

    queue.enqueue(_mod(1), _file, 'zzz');
    queue.enqueue(_mod(2), _file, 'zzz');
    await pumpEventQueue(times: 20);

    expect(queue.jobFor(1, 'zzz')!.status, MarketplaceJobStatus.failed);
    expect(queue.jobFor(1, 'zzz')!.error, contains('download failed'));
    expect(done, [2]);
  });

  test('the same mod is not queued twice while it is still pending', () async {
    final completer = Completer<String>();
    final queue = MarketplaceQueue(worker: (_, _) => completer.future);

    expect(queue.enqueue(_mod(1), _file, 'zzz'), isTrue);
    await pumpEventQueue();
    expect(queue.enqueue(_mod(1), _file, 'zzz'), isFalse);

    expect(queue.pending.length, 1);
    completer.complete('ok');
  });

  test('the same mod can be installed again once it finished', () async {
    final queue = MarketplaceQueue(worker: (_, _) async => 'ok');

    queue.enqueue(_mod(1), _file, 'zzz');
    await pumpEventQueue(times: 10);

    expect(queue.enqueue(_mod(1), _file, 'zzz'), isTrue);
  });

  test('the same mod for another game is its own job', () async {
    final completer = Completer<String>();
    final queue = MarketplaceQueue(worker: (_, _) => completer.future);

    queue.enqueue(_mod(1), _file, 'zzz');
    await pumpEventQueue();

    expect(queue.enqueue(_mod(1), _file, 'nte'), isTrue);
    expect(queue.value.length, 2);
    completer.complete('ok');
  });

  test('progress updates reach the job', () async {
    final queue = MarketplaceQueue(
      worker: (job, onProgress) async {
        onProgress(0.5);
        return 'ok';
      },
    );

    queue.enqueue(_mod(1), _file, 'zzz');
    await pumpEventQueue(times: 10);

    expect(queue.value.single.progress, 0.5);
  });

  test('the queue lives in the provider scope, not in a screen', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final first = container.read(marketplaceQueueProvider);
    final second = container.read(marketplaceQueueProvider);

    expect(identical(first, second), isTrue);

    // Would throw if a screen had disposed it on its way out, which is exactly
    // what used to cancel running downloads.
    void listener() {}
    first.addListener(listener);
    first.removeListener(listener);
  });

  test('finished jobs can be cleared, pending ones stay', () async {
    final completer = Completer<String>();
    final queue = MarketplaceQueue(
      worker: (job, _) => job.mod.id == 1 ? Future.value('ok') : completer.future,
    );

    queue.enqueue(_mod(1), _file, 'zzz');
    await pumpEventQueue(times: 10);
    queue.enqueue(_mod(2), _file, 'zzz');
    await pumpEventQueue();

    queue.clearFinished();

    expect(queue.value.map((job) => job.mod.id), [2]);
    completer.complete('ok');
  });
}
