import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/mock/mock_services.dart';
import 'package:hrismob/models/auth_result.dart';
import 'package:hrismob/models/bulletin.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/services/api_client.dart';
import 'package:hrismob/services/auth_service.dart';
import 'package:hrismob/services/authenticated_api_client.dart';
import 'package:hrismob/services/hybrid_hris_repository.dart';
import 'package:hrismob/services/secure_session_store.dart';
import 'package:hrismob/services/session_controller.dart';
import 'package:hrismob/services/upload_image_url_resolver.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _employee = Employee(
  employeeNumber: 'EMP1001',
  role: UserRole.staff,
  firstName: 'Test',
  lastName: 'Employee',
);

class _Store implements SessionStore {
  StoredSession? value = const StoredSession(
    token: 'token',
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
  Future<AuthenticatedSession?> restoreSession() async => null;
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

HybridHrisRepository _repository(MockClient httpClient) {
  final store = _Store();
  final session = SessionController(_Auth(store));
  return HybridHrisRepository(
    mockRepository: MockHrisRepository(latency: Duration.zero),
    api: AuthenticatedApiClient(
      ApiClient(Uri.parse('https://hris.example.test'), httpClient: httpClient),
      store,
      session,
    ),
    imageUrls: UploadImageUrlResolver(
      Uri.parse('https://hris.example.test/api'),
    ),
    clock: () => DateTime(2026, 10, 16, 23, 30),
  );
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

void main() {
  test('parses object/array dates, clips ranges, groups duplicates and filters scope', () async {
    final requested = <String>[];
    final repository = _repository(
      MockClient((request) async {
        requested.add(request.url.path);
        expect(request.url.queryParameters, {
          'startDate': '2026-10-09',
          'endDate': '2027-10-17',
        });
        if (request.url.path.endsWith('/holiday')) {
          return _json({
            'success': true,
            'byDate': {
              '2026-10-08': {'id': 1, 'title': 'Clipped', 'branch': null},
              '2026-10-09': {
                'id': 1,
                'title': 'Clipped',
                'branch': null,
                'image': '/uploads/holiday.jpg',
              },
              '2026-10-10': [
                {
                  'id': 1,
                  'title': 'Clipped',
                  'branch': null,
                  'image': '/uploads/different.png',
                },
                {
                  'id': 2,
                  'title': 'Same day',
                  'branch': null,
                  'image': 'https://external.example/tracker.png',
                },
                {'id': 3, 'title': 'Branch only', 'branch': 4},
                {'id': 4, 'title': 'Ambiguous'},
              ],
              'not-a-date': {'id': 5, 'title': 'Bad date', 'branch': null},
            },
          });
        }
        return _json({
          'success': true,
          'byDate': {
            '2026-10-11': [
              {
                'id': 's1',
                'title': 'All employees',
                'reason': 'Weather',
                'branch': null,
                'personnel_scope': 'all',
                'image': '/uploads/suspension.webp',
              },
              {
                'id': 's2',
                'title': 'Academic only',
                'branch': null,
                'personnel_scope': 'academic',
              },
            ],
            '2027-10-18': {
              'id': 's1',
              'title': 'All employees',
              'branch': null,
              'personnel_scope': 'all',
            },
          },
        });
      }),
    );

    final events = await repository.fetchBulletins();

    expect(
      requested,
      containsAll(['/attendance/api/holiday', '/attendance/api/suspensions']),
    );
    expect(events, hasLength(3));
    final clipped = events.singleWhere((event) => event.id == '1');
    expect(clipped.start, DateTime(2026, 10, 9));
    expect(clipped.end, DateTime(2026, 10, 10));
    expect(
      clipped.imageUrl,
      Uri.parse('https://hris.example.test/uploads/holiday.jpg'),
    );
    expect(
      events.where((event) => event.kind == BulletinKind.holiday),
      hasLength(2),
    );
    expect(
      events.singleWhere((event) => event.id == '2').start,
      DateTime(2026, 10, 10),
    );
    expect(events.singleWhere((event) => event.id == '2').imageUrl, isNull);
    final suspension = events.singleWhere(
      (event) => event.kind == BulletinKind.suspension,
    );
    expect(suspension.title, 'All employees');
    expect(suspension.about, 'Weather');
    expect(
      suspension.imageUrl,
      Uri.parse('https://hris.example.test/uploads/suspension.webp'),
    );
  });

  test(
    'coalesces requests and reloads both endpoints after invalidation',
    () async {
      var calls = 0;
      final repository = _repository(
        MockClient((_) async {
          calls++;
          return _json({'success': true, 'byDate': {}});
        }),
      );

      await Future.wait([
        repository.fetchBulletins(),
        repository.fetchBulletins(),
      ]);
      expect(calls, 2);
      repository.invalidateHomeEvents();
      await repository.fetchBulletins();
      expect(calls, 4);
    },
  );

  test(
    'malformed and partially failed responses fail without mock fallback',
    () async {
      final malformed = _repository(
        MockClient(
          (request) async => request.url.path.endsWith('/holiday')
              ? _json({'success': true, 'byDate': {}})
              : _json({'success': true, 'byDate': 'wrong'}),
        ),
      );
      await expectLater(
        malformed.fetchBulletins(),
        throwsA(isA<HomeDataException>()),
      );

      final partial = _repository(
        MockClient(
          (request) async => request.url.path.endsWith('/holiday')
              ? _json({'success': true, 'byDate': {}})
              : _json({'error': 'internal database detail'}, 500),
        ),
      );
      await expectLater(
        partial.fetchBulletins(),
        throwsA(
          isA<HomeDataException>().having(
            (error) => error.message,
            'safe error',
            isNot(contains('database')),
          ),
        ),
      );
    },
  );
}
