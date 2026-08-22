import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/utils/cancellation_token.dart';
import 'package:modlinq/utils/reload_queue.dart';

void main() {
  late ReloadQueue queue;

  setUp(() => queue = ReloadQueue());

  /// A task that only finishes when the test says so.
  ({
    Future<void> Function(CancellationToken) task,
    Completer<void> gate,
    List<String> ran,
  })
  blockingTask(String label) {
    final gate = Completer<void>();
    final ran = <String>[];
    return (
      task: (_) async {
        ran.add(label);
        await gate.future;
      },
      gate: gate,
      ran: ran,
    );
  }

  test('runs the task when nothing is in flight', () async {
    final ran = <String>[];

    await queue.run((_) async => ran.add('a'));

    expect(ran, ['a']);
  });

  test('replays a request that arrived while a task was running', () async {
    final first = blockingTask('first');
    final replayed = <String>[];

    final running = queue.run(first.task);
    final dropped = queue.run((_) async => replayed.add('second'));
    await dropped;

    expect(replayed, isEmpty, reason: 'must wait for the running task');

    first.gate.complete();
    await running;

    expect(replayed, ['second']);
  });

  test('replays only the newest request', () async {
    final first = blockingTask('first');
    final replayed = <String>[];

    final running = queue.run(first.task);
    await queue.run((_) async => replayed.add('second'));
    await queue.run((_) async => replayed.add('third'));

    first.gate.complete();
    await running;

    expect(replayed, ['third']);
  });

  test('marks the running task superseded once a request arrives', () async {
    final first = blockingTask('first');

    final running = queue.run(first.task);
    expect(queue.isSuperseded, isFalse);

    await queue.run((_) async {});
    expect(queue.isSuperseded, isTrue);

    first.gate.complete();
    await running;
  });

  test('does not consider the replayed task superseded', () async {
    final first = blockingTask('first');
    bool? supersededDuringReplay;

    final running = queue.run(first.task);
    await queue.run((_) async => supersededDuringReplay = queue.isSuperseded);

    first.gate.complete();
    await running;

    expect(supersededDuringReplay, isFalse);
  });

  test('reports whether a task is in flight', () async {
    final first = blockingTask('first');
    expect(queue.isRunning, isFalse);

    final running = queue.run(first.task);
    expect(queue.isRunning, isTrue);

    first.gate.complete();
    await running;

    expect(queue.isRunning, isFalse);
  });

  test('still replays the queued request when the running task throws', () async {
    final gate = Completer<void>();
    final replayed = <String>[];

    final running = queue.run((_) async {
      await gate.future;
      throw StateError('load failed');
    });
    await queue.run((_) async => replayed.add('second'));

    gate.complete();
    await running;

    expect(replayed, ['second']);
  });

  test('cancels the running task as soon as a newer request arrives', () async {
    final gate = Completer<void>();
    CancellationToken? seen;

    final running = queue.run((token) async {
      seen = token;
      await gate.future;
    });

    expect(seen!.isCancelled, isFalse);

    await queue.run((_) async {});
    expect(seen!.isCancelled, isTrue, reason: 'switch must abort the load');

    gate.complete();
    await running;
  });

  test('hands the replayed task a fresh, uncancelled token', () async {
    final gate = Completer<void>();
    CancellationToken? replayToken;

    final running = queue.run((_) async => gate.future);
    await queue.run((token) async => replayToken = token);

    gate.complete();
    await running;

    expect(replayToken, isNotNull);
    expect(replayToken!.isCancelled, isFalse);
  });

  test('rethrows a failure when no newer request is waiting', () async {
    expect(
      () => queue.run((_) async => throw StateError('load failed')),
      throwsA(isA<StateError>()),
    );
  });

  test('accepts new work again after a failure', () async {
    try {
      await queue.run((_) async => throw StateError('load failed'));
    } catch (_) {}

    final ran = <String>[];
    await queue.run((_) async => ran.add('after'));

    expect(ran, ['after']);
    expect(queue.isRunning, isFalse);
  });
}
