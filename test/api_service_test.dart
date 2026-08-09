import 'package:flutter_test/flutter_test.dart';

import 'package:robotsix_chat_mobile/services/api_service.dart';

void main() {
  group('ApiService', () {
    test('can be constructed with baseUrl and optional token', () {
      final svc = ApiService(baseUrl: 'https://chat.example.com');
      expect(svc.baseUrl, 'https://chat.example.com');
      expect(svc.token, isNull);

      final svcWithToken =
          ApiService(baseUrl: 'https://chat.example.com', token: 'tok-123');
      expect(svcWithToken.token, 'tok-123');
    });

    test('constructor is const', () {
      const svc = ApiService(baseUrl: 'https://chat.example.com');
      expect(svc.baseUrl, 'https://chat.example.com');
    });
  });

  group('ApiException', () {
    test('stores statusCode and body', () {
      const ex = ApiException(404, 'Not Found');
      expect(ex.statusCode, 404);
      expect(ex.body, 'Not Found');
    });

    test('toString includes status and body', () {
      const ex = ApiException(500, 'Internal Server Error');
      expect(ex.toString(), contains('500'));
      expect(ex.toString(), contains('Internal Server Error'));
    });
  });
}
