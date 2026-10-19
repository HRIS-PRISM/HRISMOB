// MOCK SERVICES FOR UI DEVELOPMENT ONLY.
//
// They never contact the HRIS backend or database. Sign-in is simulated:
// the password is not checked and nothing is verified by the HRIS.

import '../models/attendance.dart';
import '../models/auth_result.dart';
import '../models/bulletin.dart';
import '../models/employee.dart';
import '../services/auth_service.dart';
import '../services/hris_repository.dart';
import 'mock_data.dart';

const _latency = Duration(milliseconds: 600);
const _personalAttendanceFixtureEmployee = 'SAMPLE1001';

class MockAuthService implements AuthService {
  MockAuthService({this.latency = _latency});

  final Duration latency;

  @override
  bool get isMock => true;

  @override
  Future<void> clearCredentials() async {}

  @override
  Future<AuthResult> signIn({
    required String employeeNumber,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final employee = findMockEmployee(employeeNumber);
    // Same wording the backend returns for an unknown employee number.
    if (employee == null) throw const AuthException('User not found');
    return AuthenticatedSession(employee: employee);
  }

  @override
  Future<AuthenticatedSession?> restoreSession() async => null;

  @override
  Future<MfaChallenge> resendMfa(MfaChallenge challenge) =>
      throw const AuthException('MFA is not used by mock authentication.');

  @override
  Future<AuthenticatedSession> verifyMfa({
    required MfaChallenge challenge,
    required String code,
  }) => throw const AuthException('MFA is not used by mock authentication.');

  @override
  Future<void> signOut() async {}
}

class MockHrisRepository implements HrisRepository {
  MockHrisRepository({DateTime Function()? clock, this.latency = _latency})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final Duration latency;

  @override
  bool get isMock => true;

  @override
  bool get homeEventsAreLive => false;

  @override
  void invalidateHomeEvents() {}

  @override
  Future<Employee> fetchEmployee(String employeeNumber) async {
    await Future<void>.delayed(latency);
    final employee = findMockEmployee(employeeNumber);
    if (employee == null) throw StateError('No sample employee');
    return employee;
  }

  @override
  Future<List<AttendancePunch>> fetchPunches(
    String employeeNumber, {
    required DateTime start,
    required DateTime end,
  }) async {
    await Future<void>.delayed(latency);
    final first = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    return buildMockPunches(
      employeeNumber,
      _clock(),
    ).where((p) => !p.day.isBefore(first) && !p.day.isAfter(last)).toList();
  }

  @override
  Future<PersonalAttendancePage> fetchPersonalAttendance(
    PersonalAttendanceQuery query,
  ) async {
    await Future<void>.delayed(latency);
    final records =
        buildMockPunches(_personalAttendanceFixtureEmployee, _clock()).where((
          punch,
        ) {
          final day = DateTime(punch.at.year, punch.at.month, punch.at.day);
          return !day.isBefore(query.start) && !day.isAfter(query.end);
        }).toList()..sort((a, b) => a.at.compareTo(b.at));
    if (query.sort == 'desc') {
      records.sort((a, b) => b.at.compareTo(a.at));
    }

    final total = records.length;
    final offset = (query.page - 1) * query.pageSize;
    final page = offset >= total
        ? const <AttendancePunch>[]
        : records.skip(offset).take(query.pageSize).toList();
    return PersonalAttendancePage(
      records: List.unmodifiable(page),
      total: total,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<OfficialTime?> fetchOfficialTime(
    String employeeNumber,
    DateTime date,
  ) async {
    await Future<void>.delayed(latency);
    return mockOfficialTimeAssigned.contains(employeeNumber)
        ? mockOfficialTime
        : null;
  }

  @override
  Future<AttendanceMonth> fetchAttendanceMonth(
    String employeeNumber, {
    required int year,
    required int month,
  }) async {
    await Future<void>.delayed(latency);
    final employee = findMockEmployee(employeeNumber);
    return buildMockAttendanceMonth(
      employeeNumber,
      year,
      month,
      _clock(),
      employee?.isJobOrder ?? false,
    );
  }

  @override
  Future<List<Bulletin>> fetchBulletins() async {
    await Future<void>.delayed(latency);
    return buildMockBulletins(_clock());
  }
}
