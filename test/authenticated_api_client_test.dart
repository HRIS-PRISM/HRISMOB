import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/models/auth_result.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/services/api_client.dart';
import 'package:hrismob/services/auth_service.dart';
import 'package:hrismob/services/authenticated_api_client.dart';
import 'package:hrismob/services/secure_session_store.dart';
import 'package:hrismob/services/session_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _employee = Employee(
  employeeNumber: 'EMP1001',
  role: UserRole.staff,
  firstName: 'Test',
  lastName: 'Employee',
);

class _MemoryStore implements SessionStore {
  StoredSession? value;
  int clears = 0;

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }

  @override
  Future<StoredSession?> read() async => value;

  @override
  Future<void> write(StoredSession session) async => value = session;
}

class _StoreAuth implements AuthService {
  _StoreAuth(this.store);
  final _MemoryStore store;

  @override
  bool get isMock => false;
  @override
  Future<void> clearCredentials() => store.clear();
  @override
  Future<AuthenticatedSession?> restoreSession() async =>
      const AuthenticatedSession(employee: _employee, isProvisional: true);
  @override
  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<AuthenticatedSession> verifyMfa({
    required MfaChallenge challenge,
    required String code,
  }) => throw UnimplementedError();
  @override
  Future<MfaChallenge> resendMfa(MfaChallenge challenge) =>
      throw UnimplementedError();
}

StoredSession _stored(String token) =>
    StoredSession(token: token, employee: _employee, isDefaultPassword: false);

Future<(AuthenticatedApiClient, SessionController, _MemoryStore)> _subject(
  MockClient httpClient,
) async {
  final store = _MemoryStore()..value = _stored('token-one');
  final session = SessionController(_StoreAuth(store));
  await session.restoreSession();
  return (
    AuthenticatedApiClient(
      ApiClient(Uri.parse('https://hris.example.test'), httpClient: httpClient),
      store,
      session,
    ),
    session,
    store,
  );
}

void main() {
  test(
    'sends exact GET query and bearer token, then validates session',
    () async {
      late http.Request captured;
      final (client, session, _) = await _subject(
        MockClient((request) async {
          captured = request;
          return http.Response('{"success":true,"byDate":{}}', 200);
        }),
      );

      await client.get(
        '/attendance/api/holiday',
        query: {'startDate': '2026-10-09', 'endDate': '2027-10-17'},
      );

      expect(captured.method, 'GET');
      expect(captured.url.path, '/attendance/api/holiday');
      expect(captured.url.queryParameters['startDate'], '2026-10-09');
      expect(captured.url.queryParameters['endDate'], '2027-10-17');
      expect(captured.headers['authorization'], 'Bearer token-one');
      expect(session.isProvisional, isFalse);
    },
  );

  test('sends POST body and bearer token, then validates session', () async {
    late http.Request captured;
    final (client, session, _) = await _subject(
      MockClient((request) async {
        captured = request;
        return http.Response(
          '{"data":[],"total":0,"page":1,"pageSize":50}',
          200,
        );
      }),
    );

    await client.post(
      '/attendance/api/me/attendance',
      body: {
        'startDate': '2026-10-01',
        'endDate': '2026-10-19',
        'page': 1,
        'pageSize': 50,
        'sort': 'desc',
      },
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/attendance/api/me/attendance');
    expect(captured.headers['authorization'], 'Bearer token-one');
    expect(jsonDecode(captured.body), {
      'startDate': '2026-10-01',
      'endDate': '2026-10-19',
      'page': 1,
      'pageSize': 50,
      'sort': 'desc',
    });
    expect(session.isProvisional, isFalse);
  });

  test('SESSION_INVALID clears the current session', () async {
    final (client, session, store) = await _subject(
      MockClient(
        (_) async =>
            http.Response(jsonEncode({'code': 'SESSION_INVALID'}), 401),
      ),
    );

    await expectLater(
      client.get('/attendance/api/holiday'),
      throwsA(isA<ProtectedApiException>()),
    );
    expect(store.value, isNull);
    expect(session.isSignedIn, isFalse);
  });

  test('stale success cannot validate a newer session', () async {
    final response = Completer<http.Response>();
    final (client, session, store) = await _subject(
      MockClient((_) => response.future),
    );
    final request = client.get('/attendance/api/holiday');
    store.value = _stored('token-two');
    response.complete(http.Response('{"success":true,"byDate":{}}', 200));

    await request;
    expect(session.isProvisional, isTrue);
    expect(store.value?.token, 'token-two');
  });

  test('stale invalid response cannot clear a newer session', () async {
    final response = Completer<http.Response>();
    final (client, session, store) = await _subject(
      MockClient((_) => response.future),
    );
    final request = client.get('/attendance/api/holiday');
    store.value = _stored('token-two');
    response.complete(http.Response('{"code":"SESSION_INVALID"}', 401));

    await expectLater(request, throwsA(isA<ProtectedApiException>()));
    expect(store.value?.token, 'token-two');
    expect(session.isSignedIn, isTrue);
  });

  test('network and server errors do not invalidate the session', () async {
    final (client, session, store) = await _subject(
      MockClient(
        (_) async => http.Response('{"error":"database detail"}', 500),
      ),
    );

    await expectLater(
      client.get('/attendance/api/suspensions'),
      throwsA(
        isA<ProtectedApiException>().having(
          (error) => error.message,
          'safe message',
          isNot(contains('database')),
        ),
      ),
    );
    expect(store.value, isNotNull);
    expect(session.isSignedIn, isTrue);
    expect(session.isProvisional, isTrue);
  });
}
