import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/mock/mock_services.dart';
import 'package:hrismob/models/auth_result.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/services/api_client.dart';
import 'package:hrismob/services/auth_service.dart';
import 'package:hrismob/services/authenticated_api_client.dart';
import 'package:hrismob/services/hris_repository.dart';
import 'package:hrismob/services/hybrid_hris_repository.dart';
import 'package:hrismob/services/secure_session_store.dart';
import 'package:hrismob/services/session_controller.dart';
import 'package:hrismob/services/upload_image_url_resolver.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _employee = Employee(employeeNumber: 'EMP1001', role: UserRole.staff);

class _Store implements SessionStore {
  StoredSession? value = const StoredSession(
    token: 'session-token',
    employee: _employee,
    isDefaultPassword: false,
  );

  @override
  Future<void> clear() async => value = null;

  @override
  Future<StoredSession?> read() async => value;

  @override
  Future<void> write(StoredSession session) async => value = session;
}

class _Auth implements AuthService {
  _Auth(this.store);

  final _Store store;

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

HybridHrisRepository _repository(MockClient client, _Store store) {
  final session = SessionController(_Auth(store));
  return HybridHrisRepository(
    mockRepository: MockHrisRepository(latency: Duration.zero),
    api: AuthenticatedApiClient(
      ApiClient(Uri.parse('https://hris.example.test'), httpClient: client),
      store,
      session,
    ),
    imageUrls: UploadImageUrlResolver(Uri.parse('https://hris.example.test')),
  );
}

Map<String, Object?> _record(int timestamp, {int state = 1}) => {
  'PersonID': 'EMP1001',
  'AttendanceState': state,
  'AttendanceDateTime': timestamp,
  'DeviceName': 'Main Gate',
  'Branch': 0,
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  final query = PersonalAttendanceQuery(
    start: DateTime(2026, 10, 1),
    end: DateTime(2026, 10, 19),
  );

  test(
    'posts the selector-free paged request and parses the response',
    () async {
      late http.Request request;
      final store = _Store();
      final repository = _repository(
        MockClient((captured) async {
          request = captured;
          return _json({
            'data': [_record(1792107000000)],
            'total': 2,
            'page': 1,
            'pageSize': 50,
          });
        }),
        store,
      );

      final result = await repository.fetchPersonalAttendance(query);

      expect(request.method, 'POST');
      expect(request.url.path, '/attendance/api/me/attendance');
      expect(request.headers['authorization'], 'Bearer session-token');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {
        'startDate': '2026-10-01',
        'endDate': '2026-10-19',
        'page': 1,
        'pageSize': 50,
        'sort': 'desc',
      });
      for (final forbidden in const [
        'personID',
        'personId',
        'employeeNumber',
        'employee_number',
        'employeeID',
      ]) {
        expect(body.containsKey(forbidden), isFalse);
      }
      expect(result.total, 2);
      expect(result.records, hasLength(1));
      expect(result.hasMore, isTrue);
    },
  );

  test(
    'query validates calendar order, pagination, and sort before dispatch',
    () {
      expect(
        () => PersonalAttendanceQuery(
          start: DateTime(2026, 10, 2),
          end: DateTime(2026, 10, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => PersonalAttendanceQuery(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 1),
          page: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PersonalAttendanceQuery(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 1),
          pageSize: 201,
        ),
        throwsArgumentError,
      );
      expect(
        () => PersonalAttendanceQuery(
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 1),
          sort: 'newest',
        ),
        throwsArgumentError,
      );
    },
  );

  test('mock mode filters, sorts, and pages deterministically', () async {
    final repository = MockHrisRepository(
      clock: () => DateTime(2026, 10, 19, 18),
      latency: Duration.zero,
    );
    final ascending = await repository.fetchPersonalAttendance(
      PersonalAttendanceQuery(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 19),
        pageSize: 2,
        sort: 'asc',
      ),
    );
    final descending = await repository.fetchPersonalAttendance(
      PersonalAttendanceQuery(
        start: DateTime(2026, 10, 1),
        end: DateTime(2026, 10, 19),
        page: 2,
        pageSize: 2,
        sort: 'desc',
      ),
    );

    expect(ascending.records, hasLength(2));
    expect(ascending.total, greaterThan(2));
    expect(ascending.hasMore, isTrue);
    expect(ascending.records[0].at.isBefore(ascending.records[1].at), isTrue);
    expect(descending.records, hasLength(2));
    expect(descending.records[0].at.isAfter(descending.records[1].at), isTrue);
  });

  test(
    'session expiry, server errors, and malformed data stay visible',
    () async {
      final cases = [
        _json({'code': 'SESSION_INVALID'}, 401),
        _json({'error': 'database detail'}, 500),
        _json({'data': 'invalid', 'total': 0, 'page': 1, 'pageSize': 50}),
      ];
      for (final response in cases) {
        final store = _Store();
        final repository = _repository(
          MockClient((_) async => response),
          store,
        );
        await expectLater(
          repository.fetchPersonalAttendance(query),
          throwsA(isA<PersonalAttendanceDataException>()),
        );
        if (response.statusCode == 401) {
          expect(store.value, isNull);
        } else {
          expect(store.value, isNotNull);
        }
      }
    },
  );
}
