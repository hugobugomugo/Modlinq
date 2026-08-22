import 'package:flutter_test/flutter_test.dart';

import 'package:modlinq/utils/cancellation_token.dart';

void main() {
  test('starts out not cancelled', () {
    expect(CancellationToken().isCancelled, isFalse);
  });

  test('reports cancellation after cancel', () {
    final token = CancellationToken()..cancel();

    expect(token.isCancelled, isTrue);
  });

  test('stays cancelled when cancelled twice', () {
    final token = CancellationToken()
      ..cancel()
      ..cancel();

    expect(token.isCancelled, isTrue);
  });

  test('treats a null token as never cancelled', () {
    expect(CancellationToken.isCancelledOrNull(null), isFalse);
  });

  test('reads through to a real token', () {
    final token = CancellationToken();

    expect(CancellationToken.isCancelledOrNull(token), isFalse);
    token.cancel();
    expect(CancellationToken.isCancelledOrNull(token), isTrue);
  });
}
