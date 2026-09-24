import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/app_log.dart';
import 'package:modlinq/services/ui_stall_watchdog.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('modlinq-log');
    AppLog.clear();
    AppLog.init(directory: tmp.path);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  File logFile() => File(p.join(tmp.path, AppLog.fileName));

  group('log file', () {
    test('writes level and message to disk', () {
      AppLog.info('marketplace install started');

      final content = logFile().readAsStringSync();
      expect(content, contains('INFO'));
      expect(content, contains('marketplace install started'));
    });

    test('an error carries its exception and stack trace', () {
      AppLog.error(
        'install failed',
        error: StateError('checksum mismatch'),
        stack: StackTrace.fromString('#0 fake frame'),
      );

      final content = logFile().readAsStringSync();
      expect(content, contains('ERROR'));
      expect(content, contains('checksum mismatch'));
      expect(content, contains('#0 fake frame'));
    });

    test('details are indented under their line, not flattened', () {
      AppLog.warn('two lines', details: 'first\nsecond');

      final lines = logFile().readAsLinesSync();
      expect(lines[0], contains('two lines'));
      expect(lines[1], '    first');
      expect(lines[2], '    second');
    });

    test('a full log rotates into a single previous file', () {
      final filler = 'x' * 4096;
      // 2 MB cap, so this crosses it without writing forever.
      for (var i = 0; i < 600; i++) {
        AppLog.info(filler);
      }

      expect(File(p.join(tmp.path, AppLog.previousFileName)).existsSync(), isTrue);
      expect(logFile().lengthSync(), lessThan(AppLog.maxFileBytes));
    });

    test('logging keeps working after a rotation', () {
      for (var i = 0; i < 600; i++) {
        AppLog.info('x' * 4096);
      }

      AppLog.info('after rotation');

      expect(logFile().readAsStringSync(), contains('after rotation'));
    });
  });

  group('in memory tail', () {
    test('keeps the newest entries in order', () {
      AppLog.info('first');
      AppLog.info('second');
      AppLog.info('third');

      expect(
        AppLog.recent(limit: 2).map((e) => e.message),
        ['second', 'third'],
      );
    });

    test('never grows past the cap', () {
      for (var i = 0; i < AppLog.maxEntriesInMemory + 50; i++) {
        AppLog.info('line $i');
      }

      expect(AppLog.recent().length, AppLog.maxEntriesInMemory);
      expect(AppLog.recent().last.message, 'line ${AppLog.maxEntriesInMemory + 49}');
    });

    test('the copyable text contains the formatted lines', () {
      AppLog.warn('careful');

      expect(AppLog.recentAsText(), contains('WARN'));
      expect(AppLog.recentAsText(), contains('careful'));
    });
  });

  group('ui stall watchdog', () {
    test('a tick that arrives on time reports nothing', () {
      var clock = DateTime(2026);
      final stalls = <Duration>[];

      final watchdog = UiStallWatchdog(
        interval: const Duration(milliseconds: 500),
        threshold: const Duration(seconds: 2),
        now: () => clock,
        onStall: stalls.add,
      );

      watchdog.tick();
      clock = clock.add(const Duration(milliseconds: 520));
      watchdog.tick();

      expect(stalls, isEmpty);
    });

    test('a late tick reports how long the thread was blocked', () {
      var clock = DateTime(2026);
      final stalls = <Duration>[];

      final watchdog = UiStallWatchdog(
        interval: const Duration(milliseconds: 500),
        threshold: const Duration(seconds: 2),
        now: () => clock,
        onStall: stalls.add,
      );

      watchdog.tick();
      // 6.5 s between ticks: 6 s of that is the block itself.
      clock = clock.add(const Duration(milliseconds: 6500));
      watchdog.tick();

      expect(stalls.single, const Duration(milliseconds: 6000));
    });

    test('a stall just under the threshold is ignored', () {
      var clock = DateTime(2026);
      final stalls = <Duration>[];

      final watchdog = UiStallWatchdog(
        interval: const Duration(milliseconds: 500),
        threshold: const Duration(seconds: 2),
        now: () => clock,
        onStall: stalls.add,
      );

      watchdog.tick();
      clock = clock.add(const Duration(milliseconds: 2400));
      watchdog.tick();

      expect(stalls, isEmpty);
    });
  });
}
