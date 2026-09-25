import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/services/game_process_watch.dart';

ProcessResult _out(String stdout) => ProcessResult(0, 0, stdout, '');

void main() {
  test('a listed process counts as running', () async {
    final watch = GameProcessWatch(
      supported: true,
      list: (exe) async => _out('$exe  1234 Console  1  512 K'),
    );

    expect(await watch.isRunning('NTEGlobalGame.exe'), isTrue);
  });

  test('the "no tasks" reply counts as not running', () async {
    final watch = GameProcessWatch(
      supported: true,
      list: (_) async => _out('INFO: No tasks are running which match.'),
    );

    expect(await watch.isRunning('NTEGlobalGame.exe'), isFalse);
  });

  test('an unusable platform answers no without asking', () async {
    var asked = false;
    final watch = GameProcessWatch(
      supported: false,
      list: (exe) async {
        asked = true;
        return _out(exe);
      },
    );

    expect(await watch.isRunning('NTEGlobalGame.exe'), isFalse);
    expect(asked, isFalse);
  });

  test('a failed lookup is not running rather than a crash', () async {
    final watch = GameProcessWatch(
      supported: true,
      list: (_) async => throw const ProcessException('tasklist', []),
    );

    expect(await watch.isRunning('NTEGlobalGame.exe'), isFalse);
  });
}
