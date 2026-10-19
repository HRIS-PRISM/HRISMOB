import '../models/attendance.dart';
import '../models/bulletin.dart';
import '../models/employee.dart';

/// Read-only access to the signed-in employee's own HRIS data.
///
/// There are no write operations by design. Every call is for the signed-in
/// employee only; the real backend must enforce that (Phase 4).
abstract class HrisRepository {
  bool get isMock;

  /// Whether Home holidays and suspensions use the approved protected APIs.
  bool get homeEventsAreLive => false;

  /// Clears only the Home holiday/suspension request cache.
  void invalidateHomeEvents() {}

  Future<Employee> fetchEmployee(String employeeNumber);

  /// Device punches on dates from [start] to [end] inclusive (Asia/Manila).
  Future<List<AttendancePunch>> fetchPunches(
    String employeeNumber, {
    required DateTime start,
    required DateTime end,
  });

  /// One server-paged set of the signed-in user's raw attendance punches.
  ///
  /// Unlike [fetchPunches], this is deliberately selector-free: real mode
  /// derives the employee identity from the authenticated backend session.
  Future<PersonalAttendancePage> fetchPersonalAttendance(
    PersonalAttendanceQuery query,
  );

  /// Official schedule on [date], or null when none is assigned.
  Future<OfficialTime?> fetchOfficialTime(String employeeNumber, DateTime date);

  /// Day codes for the Home "My Attendance" widget ([month] is 1–12).
  Future<AttendanceMonth> fetchAttendanceMonth(
    String employeeNumber, {
    required int year,
    required int month,
  });

  /// Home notices. In real mode this contains only approved, institution-wide
  /// holidays and suspensions; announcements remain disconnected.
  Future<List<Bulletin>> fetchBulletins();
}

/// A validated, Asia/Manila calendar-date request for personal attendance.
///
/// This contains no employee identifier. Its JSON shape is the only request
/// body allowed for `POST /attendance/api/me/attendance`.
class PersonalAttendanceQuery {
  factory PersonalAttendanceQuery({
    required DateTime start,
    required DateTime end,
    int page = 1,
    int pageSize = defaultPageSize,
    String sort = 'desc',
  }) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    if (endDate.isBefore(startDate)) {
      throw ArgumentError.value(end, 'end', 'must not be before start');
    }
    if (page < 1) {
      throw ArgumentError.value(page, 'page', 'must be at least 1');
    }
    if (pageSize < 1 || pageSize > 200) {
      throw ArgumentError.value(pageSize, 'pageSize', 'must be from 1 to 200');
    }
    if (sort != 'asc' && sort != 'desc') {
      throw ArgumentError.value(sort, 'sort', 'must be asc or desc');
    }
    return PersonalAttendanceQuery._(
      start: startDate,
      end: endDate,
      page: page,
      pageSize: pageSize,
      sort: sort,
    );
  }

  const PersonalAttendanceQuery._({
    required this.start,
    required this.end,
    required this.page,
    required this.pageSize,
    required this.sort,
  });

  static const int defaultPageSize = 50;

  /// Calendar dates passed through without device-timezone conversion.
  final DateTime start;
  final DateTime end;
  final int page;
  final int pageSize;
  final String sort;

  Map<String, Object?> toRequestBody() => {
    'startDate': _iso(start),
    'endDate': _iso(end),
    'page': page,
    'pageSize': pageSize,
    'sort': sort,
  };

  static String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
