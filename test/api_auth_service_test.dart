import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hrismob/models/auth_result.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/services/api_auth_service.dart';
import 'package:hrismob/services/api_client.dart';
import 'package:hrismob/services/auth_service.dart';
import 'package:hrismob/services/secure_session_store.dart';

class _MemorySessionStore implements SessionStore {
  StoredSession? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredSession?> read() async => value;

  @override
  Future<void> write(StoredSession session) async => value = session;
}

Map<String, Object?> sessionJson({String? token}) => {
  'token': token ?? _jwt(expiresIn: const Duration(hours: 1)),
  'role': 'staff',
  'employeeNumber': 'EMP1001',
  'email': 'employee@example.test',
  'username': 'Test Employee',
  'firstName': 'Test',
  'middleName': null,
  'lastName': 'Employee',
  'nameExtension': null,
  'isDefaultPassword': false,
};

String _jwt({required Duration expiresIn}) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final expiry =
      DateTime.now().toUtc().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'exp': expiry})}.signature';
}

void main() {
  test(
    'direct login uses exact contract and stores completed session',
    () async {
      late http.Request request;
      final store = _MemorySessionStore();
      final service = ApiAuthService(
        ApiClient(
          Uri.parse('https://hris.example.test'),
          httpClient: MockClient((incoming) async {
            request = incoming;
            return http.Response(jsonEncode(sessionJson()), 200);
          }),
        ),
        store,
      );

      final result = await service.signIn(
        employeeNumber: ' EMP1001 ',
        password: 'secret',
      );

      expect(result, isA<AuthenticatedSession>());
      expect(request.method, 'POST');
      expect(request.url.path, '/login');
      expect(request.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(request.body), {
        'employeeNumber': 'EMP1001',
        'password': 'secret',
      });
      expect(store.value?.employee.employeeNumber, 'EMP1001');
      expect(store.value?.token, isNotEmpty);
    },
  );

  test(
    'MFA challenge verifies with challengeId and code before storing',
    () async {
      final calls = <String>[];
      final store = _MemorySessionStore();
      final service = ApiAuthService(
        ApiClient(
          Uri.parse('https://hris.example.test'),
          httpClient: MockClient((request) async {
            calls.add(request.url.path);
            if (request.url.path == '/login') {
              return http.Response(
                jsonEncode({
                  'mfaRequired': true,
                  'challengeId': 'challenge-1',
                  'maskedEmail': 'e***@example.test',
                  'codeExpiresIn': 300,
                }),
                200,
              );
            }
            expect(jsonDecode(request.body), {
              'challengeId': 'challenge-1',
              'code': '123456',
            });
            return http.Response(
              jsonEncode({'verified': true, ...sessionJson()}),
              200,
            );
          }),
        ),
        store,
      );

      final first = await service.signIn(
        employeeNumber: 'EMP1001',
        password: 'secret',
      );
      expect(first, isA<MfaChallenge>());
      expect(store.value, isNull);

      final completed = await service.verifyMfa(
        challenge: first as MfaChallenge,
        code: '123456',
      );
      expect(completed.employee.employeeNumber, 'EMP1001');
      expect(calls, ['/login', '/verify-2fa-code']);
      expect(store.value, isNotNull);
    },
  );

  test('resend honors backend retry metadata', () async {
    final service = ApiAuthService(
      ApiClient(
        Uri.parse('https://hris.example.test'),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'Please wait before requesting another code.',
              'retryAfter': 42,
            }),
            429,
            headers: {'retry-after': '42'},
          ),
        ),
      ),
      _MemorySessionStore(),
    );

    final challenge = MfaChallenge(
      challengeId: 'challenge-1',
      maskedEmail: 'e***@example.test',
      codeExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
    await expectLater(
      service.resendMfa(challenge),
      throwsA(
        isA<AuthException>()
            .having((e) => e.statusCode, 'status', 429)
            .having((e) => e.retryAfterSeconds, 'retry', 42),
      ),
    );
  });

  test(
    'resend fails closed when the backend has deleted the challenge',
    () async {
      final service = ApiAuthService(
        ApiClient(
          Uri.parse('https://hris.example.test'),
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'error': 'Too many codes requested. Please log in again.',
              }),
              429,
            ),
          ),
        ),
        _MemorySessionStore(),
      );
      final challenge = MfaChallenge(
        challengeId: 'challenge-1',
        maskedEmail: 'e***@example.test',
        codeExpiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );

      await expectLater(
        service.resendMfa(challenge),
        throwsA(
          isA<AuthException>().having((e) => e.restart, 'restart', isTrue),
        ),
      );
    },
  );

  test(
    'malformed successful response fails closed and is not stored',
    () async {
      final store = _MemorySessionStore();
      final service = ApiAuthService(
        ApiClient(
          Uri.parse('https://hris.example.test'),
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode({'role': 'staff'}), 200),
          ),
        ),
        store,
      );

      await expectLater(
        service.signIn(employeeNumber: 'EMP1001', password: 'secret'),
        throwsA(isA<AuthException>()),
      );
      expect(store.value, isNull);
    },
  );

  test('restored session is provisional and expired JWT is removed', () async {
    final store = _MemorySessionStore();
    store.value = StoredSession(
      token: _jwt(expiresIn: const Duration(hours: 1)),
      employee: Employee.fromAuthJson(sessionJson()),
      isDefaultPassword: false,
    );
    final service = ApiAuthService(
      ApiClient(
        Uri.parse('https://hris.example.test'),
        httpClient: MockClient((_) async => http.Response('{}', 500)),
      ),
      store,
    );

    final restored = await service.restoreSession();
    expect(restored?.isProvisional, isTrue);

    store.value = StoredSession(
      token: _jwt(expiresIn: const Duration(seconds: -1)),
      employee: restored!.employee,
      isDefaultPassword: false,
    );
    expect(await service.restoreSession(), isNull);
    expect(store.value, isNull);
  });

  test('logout clears storage even when the network request fails', () async {
    final store = _MemorySessionStore()
      ..value = StoredSession(
        token: _jwt(expiresIn: const Duration(hours: 1)),
        employee: Employee.fromAuthJson(sessionJson()),
        isDefaultPassword: false,
      );
    final service = ApiAuthService(
      ApiClient(
        Uri.parse('https://hris.example.test'),
        httpClient: MockClient(
          (_) async => throw http.ClientException('offline'),
        ),
      ),
      store,
    );

    await service.signOut();
    expect(store.value, isNull);
  });
}
