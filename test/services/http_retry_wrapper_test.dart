import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:robotsix_chat_mobile/models/api_exception.dart';
import 'package:robotsix_chat_mobile/services/http_retry_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isTransientError', () {
    test('network-level failures are transient', () {
      expect(isTransientError(const SocketException('down')), isTrue);
      expect(isTransientError(http.ClientException('boom')), isTrue);
      expect(isTransientError(const HttpException('bad')), isTrue);
      expect(isTransientError(TimeoutException('slow')), isTrue);
    });

    test('5xx / 408 / 429 responses are transient', () {
      expect(isTransientError(const ApiException(500, 'err')), isTrue);
      expect(isTransientError(const ApiException(503, 'err')), isTrue);
      expect(isTransientError(const ApiException(408, 'err')), isTrue);
      expect(isTransientError(const ApiException(429, 'err')), isTrue);
    });

    test('auth failures and other 4xx are fatal', () {
      expect(isTransientError(const AuthException(401, 'no')), isFalse);
      expect(isTransientError(const AuthException(403, 'no')), isFalse);
      expect(isTransientError(const ApiException(400, 'bad')), isFalse);
      expect(isTransientError(const ApiException(404, 'gone')), isFalse);
    });

    test('malformed payloads and unknown errors are fatal', () {
      expect(isTransientError(const FormatException('bad json')), isFalse);
      expect(isTransientError(ArgumentError('nope')), isFalse);
    });
  });

  group('withRetry', () {
    test('returns the result without retrying on success', () async {
      var calls = 0;
      final result = await withRetry(() async {
        calls++;
        return 'ok';
      });
      expect(result, 'ok');
      expect(calls, 1);
    });

    test('retries a transient failure then succeeds', () async {
      var calls = 0;
      final result = await withRetry(() async {
        calls++;
        if (calls < 3) throw const SocketException('flaky');
        return 'recovered';
      });
      expect(result, 'recovered');
      expect(calls, 3);
    });

    test('gives up after maxAttempts and rethrows the last error', () async {
      var calls = 0;
      await expectLater(
        withRetry(() async {
          calls++;
          throw const SocketException('always down');
        }),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 3);
    });

    test('honours a custom maxAttempts', () async {
      var calls = 0;
      await expectLater(
        withRetry(
          () async {
            calls++;
            throw const SocketException('down');
          },
          maxAttempts: 5,
        ),
        throwsA(isA<SocketException>()),
      );
      expect(calls, 5);
    });

    test('does not retry a fatal error', () async {
      var calls = 0;
      await expectLater(
        withRetry(() async {
          calls++;
          throw const AuthException(401, 'unauthorized');
        }),
        throwsA(isA<AuthException>()),
      );
      expect(calls, 1);
    });
  });
}
