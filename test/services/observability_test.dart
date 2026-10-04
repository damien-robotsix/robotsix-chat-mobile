import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/services/observability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Observability', () {
    test('isEnabled is false when Firebase is not initialised', () {
      expect(Observability.isEnabled, isFalse);
    });

    test(
      'recordError is a no-op (completes) when Firebase is disabled',
      () async {
        await expectLater(
          Observability.recordError(
            StateError('boom'),
            StackTrace.current,
            reason: 'test',
          ),
          completes,
        );
      },
    );

    test(
      'setCustomKey is a no-op (completes) when Firebase is disabled',
      () async {
        await expectLater(
          Observability.setCustomKey('sessionId', 'none'),
          completes,
        );
      },
    );
  });
}
