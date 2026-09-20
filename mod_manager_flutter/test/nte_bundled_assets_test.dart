import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/services/nte_loader_installer.dart';

/// The install code resolves these by key, so a path renamed in pubspec or on
/// disk would only surface as a failed install on a user's machine.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = [
    NteLoaderInstaller.loaderAsiAsset,
    NteLoaderInstaller.subloaderAsset,
    NteLoaderInstaller.proxyDllAsset,
    'assets/nte_bundled/Anticensor/Anticensor.asi',
    'assets/nte_bundled/Hide_UID/Hide_UID_P.pak',
    'assets/nte_bundled/Hide_UID/Hide_UID_P.ucas',
    'assets/nte_bundled/Hide_UID/Hide_UID_P.utoc',
  ];

  for (final asset in assets) {
    test('$asset ships with the app', () async {
      final data = await rootBundle.load(asset);
      expect(data.lengthInBytes, greaterThan(0));
    });
  }
}
