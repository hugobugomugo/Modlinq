import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:modlinq/services/uninstall_service.dart';
import 'package:modlinq/services/update_service.dart';

void main() {
  late Directory tmp;
  late Directory appData;

  Directory _dir(String path, {int files = 1}) {
    final d = Directory(path)..createSync(recursive: true);
    for (var i = 0; i < files; i++) {
      File(p.join(d.path, 'f$i.bin')).writeAsStringSync('xxxxx');
    }
    return d;
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('modlinq_uninstall_');
    appData = _dir(p.join(tmp.path, 'appdata'));
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  UninstallService _service({
    List<Directory> libraries = const [],
    InstallKind installKind = InstallKind.portable,
    Future<void> Function()? removeGameInjections,
    List<String> injectionLabels = const [],
    Future<void> Function()? startAppRemoval,
  }) => UninstallService(
    appDataDir: appData,
    libraryDirs: libraries,
    installKind: installKind,
    removeGameInjections: removeGameInjections,
    gameInjectionLabels: injectionLabels,
    startAppRemoval: startAppRemoval,
  );

  test('a step with nothing to remove is not offered', () {
    final plan = _service().plan();

    // No games wired and no libraries: only app data and the app itself.
    expect(
      plan.tasks.map((t) => t.step),
      isNot(contains(UninstallStep.gameInjections)),
    );
    expect(
      plan.tasks.map((t) => t.step),
      isNot(contains(UninstallStep.modLibrary)),
    );
    expect(plan.tasks.map((t) => t.step), contains(UninstallStep.appData));
  });

  test('a managed install cannot remove the application', () {
    final plan = _service(installKind: InstallKind.managed).plan();

    expect(
      plan.tasks.map((t) => t.step),
      isNot(contains(UninstallStep.application)),
    );
  });

  test('the library size is reported so the dialog can warn', () {
    final library = _dir(p.join(tmp.path, 'library'), files: 4);

    final task = _service(libraries: [library]).plan().taskFor(
      UninstallStep.modLibrary,
    )!;

    expect(task.paths, [library.path]);
    expect(task.bytes, 4 * 5);
  });

  test('only the selected steps run', () async {
    var injectionsRemoved = false;
    final library = _dir(p.join(tmp.path, 'library'));
    final service = _service(
      libraries: [library],
      removeGameInjections: () async => injectionsRemoved = true,
      injectionLabels: const ['NTE'],
    );

    final outcome = await service.run(service.plan(), {
      UninstallStep.modLibrary,
    });

    expect(outcome.completed, [UninstallStep.modLibrary]);
    expect(library.existsSync(), isFalse);
    expect(injectionsRemoved, isFalse);
    expect(appData.existsSync(), isTrue);
  });

  test('a library inside app data survives when only app data is selected', () async {
    // The default library lives in the app data folder, so a user who keeps
    // the library and drops the config must not lose gigabytes of mods.
    final library = _dir(p.join(appData.path, 'nte_mods'), files: 3);
    final service = _service(libraries: [library]);

    await service.run(service.plan(), {UninstallStep.appData});

    expect(library.existsSync(), isTrue);
    expect(library.listSync().length, 3);
    expect(File(p.join(appData.path, 'f0.bin')).existsSync(), isFalse);
  });

  test('both selected removes the app data folder outright', () async {
    _dir(p.join(appData.path, 'nte_mods'), files: 3);
    final library = Directory(p.join(appData.path, 'nte_mods'));
    final service = _service(libraries: [library]);

    await service.run(service.plan(), {
      UninstallStep.appData,
      UninstallStep.modLibrary,
    });

    expect(appData.existsSync(), isFalse);
  });

  test('one failing step does not stop the others', () async {
    final library = _dir(p.join(tmp.path, 'library'));
    final service = _service(
      libraries: [library],
      removeGameInjections: () async => throw StateError('game folder locked'),
      injectionLabels: const ['NTE'],
    );

    final outcome = await service.run(service.plan(), {
      UninstallStep.gameInjections,
      UninstallStep.modLibrary,
    });

    expect(outcome.completed, [UninstallStep.modLibrary]);
    expect(outcome.failures.single.step, UninstallStep.gameInjections);
    expect(outcome.failures.single.error, contains('game folder locked'));
    expect(library.existsSync(), isFalse);
  });

  test('the application is removed last, after the data it owns', () async {
    final order = <String>[];
    final service = _service(
      removeGameInjections: () async => order.add('injections'),
      injectionLabels: const ['NTE'],
      startAppRemoval: () async => order.add('application'),
    );

    await service.run(service.plan(), UninstallStep.values.toSet());

    expect(order.last, 'application');
    expect(order.first, 'injections');
  });
}
