import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:modlinq/services/config_service.dart';

/// The marketplace card reads "Installed" off this list. It used to be write
/// only: deleting the mod left the id behind, so the card stayed "Installed"
/// for a mod that was no longer on disk and could not be installed again.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  Future<ConfigService> configWith([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    return ConfigService(
      await SharedPreferences.getInstance(),
      configDirectory: tmp.path,
    );
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('marketplace_installs_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('an install is remembered with the folder it landed in', () async {
    final config = await configWith();

    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Baroness Mina');

    expect(config.installedMarketplaceMods('deadlock'), ['42']);
    expect(config.marketplaceInstalls('deadlock'), {'42': 'Baroness Mina'});
  });

  test('deleting the mod puts the card back to "Install"', () async {
    final config = await configWith();
    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Baroness Mina');

    await config.forgetMarketplaceInstall('deadlock', 'Baroness Mina');

    expect(config.installedMarketplaceMods('deadlock'), isEmpty);
  });

  test('another game is left alone', () async {
    final config = await configWith();
    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Shared Name');
    await config.setMarketplaceInstalled('zzz', 7, true, name: 'Shared Name');

    await config.forgetMarketplaceInstall('deadlock', 'Shared Name');

    expect(config.installedMarketplaceMods('deadlock'), isEmpty);
    expect(config.installedMarketplaceMods('zzz'), ['7']);
  });

  test('a renamed mod can still be forgotten', () async {
    final config = await configWith();
    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Baroness Mina');

    await config.renameMarketplaceInstall('deadlock', 'Baroness Mina', 'Mina Bunny');
    expect(config.marketplaceInstalls('deadlock'), {'42': 'Mina Bunny'});

    await config.forgetMarketplaceInstall('deadlock', 'Mina Bunny');
    expect(config.installedMarketplaceMods('deadlock'), isEmpty);
  });

  test('a name with a colon survives the round trip', () async {
    // Linux allows it in a folder name, and the entry is stored as id:name.
    final config = await configWith();

    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Mina: Reloaded');

    expect(config.marketplaceInstalls('deadlock'), {'42': 'Mina: Reloaded'});
  });

  test('forgetting a name nobody holds changes nothing', () async {
    final config = await configWith();
    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Baroness Mina');

    await config.forgetMarketplaceInstall('deadlock', 'Some Other Mod');

    expect(config.installedMarketplaceMods('deadlock'), ['42']);
  });

  test('ids written before names were recorded still read as installed', () async {
    // Older config: a bare id, no folder name to match a delete against.
    final config = await configWith({
      'flutter.marketplace_installed_deadlock': ['99'],
    });

    expect(config.installedMarketplaceMods('deadlock'), ['99']);
    expect(config.marketplaceInstalls('deadlock'), {'99': null});

    await config.setMarketplaceInstalled('deadlock', 42, true, name: 'Baroness Mina');

    expect(config.marketplaceInstalls('deadlock'), {'99': null, '42': 'Baroness Mina'});
  });

  test('reinstalling an old entry gives it a name again', () async {
    final config = await configWith({
      'flutter.marketplace_installed_deadlock': ['99'],
    });

    await config.setMarketplaceInstalled('deadlock', 99, true, name: 'Narita Brian as Yamato');

    expect(config.marketplaceInstalls('deadlock'), {'99': 'Narita Brian as Yamato'});
  });
}
