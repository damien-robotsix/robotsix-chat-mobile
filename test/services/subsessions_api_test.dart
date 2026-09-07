import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:robotsix_chat_mobile/models/api_exception.dart';
import 'package:robotsix_chat_mobile/models/subsession.dart';
import 'package:robotsix_chat_mobile/services/api_service.dart';
import 'package:robotsix_chat_mobile/services/auth_provider.dart';

class MockClient extends Mock implements http.Client {}

class MockAuthProvider extends Mock implements AuthProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService subsession methods', () {
    late MockClient mockClient;
    late MockAuthProvider mockAuth;
    late ApiService apiService;

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      FlutterSecureStorage.setMockInitialValues({});
      mockClient = MockClient();
      mockAuth = MockAuthProvider();
      registerFallbackValue(Uri());
      when(() => mockAuth.requestHeaders())
          .thenAnswer((_) async => {'Authorization': 'Bearer test-token'});
      apiService = ApiService(
        baseUrl: 'https://chat.example.com',
        authProvider: mockAuth,
        client: mockClient,
      );
    });

    group('listSubsessions', () {
      test('requests /subsessions with session_id and parses the list',
          () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async {
          return http.Response(
            jsonEncode({
              'subsessions': [
                {
                  'subsession_id': 'sub-1',
                  'kind': 'periodic',
                  'owner_session_id': 'sess-1',
                  'title': 'Monitor: deploy',
                  'status': 'sleeping',
                  'runs': 3,
                  'max_runs': 100,
                },
              ],
            }),
            200,
          );
        });

        final subs = await apiService.listSubsessions('sess-1');

        expect(subs, hasLength(1));
        expect(subs.single.subsessionId, 'sub-1');
        expect(subs.single.kind, 'periodic');
        expect(subs.single.title, 'Monitor: deploy');

        final captured = verify(() => mockClient.get(
              captureAny(),
              headers: any(named: 'headers'),
            )).captured;
        expect(
          (captured.single as Uri).toString(),
          'https://chat.example.com/subsessions?session_id=sess-1',
        );
      });

      test('returns an empty list when the subsessions key is missing',
          () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('{}', 200));

        final subs = await apiService.listSubsessions('sess-1');

        expect(subs, isEmpty);
      });

      test('throws AuthException on 401', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('unauthorized', 401));

        await expectLater(
          apiService.listSubsessions('sess-1'),
          throwsA(isA<AuthException>()),
        );
      });

      test('throws ApiException on non-200', () async {
        when(() => mockClient.get(any(), headers: any(named: 'headers')))
            .thenAnswer((_) async => http.Response('boom', 500));

        await expectLater(
          apiService.listSubsessions('sess-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('closeSubsession', () {
      test('posts to /subsessions/{id}/close', () async {
        when(() => mockClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            )).thenAnswer((_) async => http.Response('{}', 200));

        await apiService.closeSubsession('sub-1');

        final captured = verify(() => mockClient.post(
              captureAny(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            )).captured;
        expect(
          (captured.single as Uri).toString(),
          'https://chat.example.com/subsessions/sub-1/close',
        );
      });

      test('throws ApiException on non-200', () async {
        when(() => mockClient.post(
              any(),
              headers: any(named: 'headers'),
              body: any(named: 'body'),
            )).thenAnswer((_) async => http.Response('gone', 404));

        await expectLater(
          apiService.closeSubsession('sub-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });
  });
}
