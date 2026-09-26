import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/elevated_file_copy.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('modlinq_copy_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File _source(String name, String body) => File(p.join(tmp.path, name))
    ..createSync(recursive: true)
    ..writeAsStringSync(body);

  test('copies into a destination folder that does not exist yet', () {
    final src = _source('a.bin', 'payload');
    final dst = p.join(tmp.path, 'deep', 'nested', 'a.bin');

    ElevatedFileCopy.copyLocal({src.path: dst});

    expect(File(dst).readAsStringSync(), 'payload');
  });

  test('overwrites a file that is already there', () {
    final src = _source('a.bin', 'new');
    final dst = p.join(tmp.path, 'out', 'a.bin');
    File(dst)
      ..createSync(recursive: true)
      ..writeAsStringSync('old');

    ElevatedFileCopy.copyLocal({src.path: dst});

    expect(File(dst).readAsStringSync(), 'new');
  });

  test('the helper reports success through its result file', () async {
    final src = _source('a.bin', 'payload');
    final dst = p.join(tmp.path, 'out', 'a.bin');
    final taskFile = File(p.join(tmp.path, 'copy.json'))
      ..writeAsStringSync(jsonEncode({src.path: dst}));

    await ElevatedFileCopy.runFromTaskFile(taskFile.path);

    final result = jsonDecode(
      File(p.join(tmp.path, 'result.json')).readAsStringSync(),
    );
    expect(result['ok'], isTrue);
    expect(File(dst).existsSync(), isTrue);
  });

  test('the helper reports failure instead of dying silently', () async {
    final taskFile = File(p.join(tmp.path, 'copy.json'))
      ..writeAsStringSync(
        jsonEncode({p.join(tmp.path, 'missing.bin'): p.join(tmp.path, 'x')}),
      );

    await ElevatedFileCopy.runFromTaskFile(taskFile.path);

    final result = jsonDecode(
      File(p.join(tmp.path, 'result.json')).readAsStringSync(),
    );
    expect(result['error'], isA<String>());
  });

  test('the helper argument is recognised only with its prefix', () {
    expect(
      ElevatedFileCopy.taskFileFromArgs(['--modlinq-copy=/tmp/t.json']),
      '/tmp/t.json',
    );
    expect(ElevatedFileCopy.taskFileFromArgs(['--other', 'x']), isNull);
  });
}
