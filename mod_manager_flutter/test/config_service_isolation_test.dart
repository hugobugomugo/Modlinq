import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/core/constants.dart';
import 'package:modlinq/services/config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('config_isolation_');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('writes into the directory it was given', () async {
    final config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );

    await config.setZzzPaths('/some/mods', '/some/links');

    final written = File(p.join(tmp.path, AppConstants.configFileName));
    expect(written.existsSync(), isTrue);
    expect(written.readAsStringSync(), contains('/some/mods'));
  });

  test('never touches the real user config when given a directory', () async {
    // Regression guard: a test that saved settings once wiped the developer's
    // own mod paths, active mods and favourites.
    final config = ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );

    await config.setZzzPaths('/some/mods', '/some/links');

    expect(
      config.debugConfigFilePath,
      p.join(tmp.path, AppConstants.configFileName),
    );
  });
}
