import '../models/attendance.dart';
import '../models/bulletin.dart';
import '../models/employee.dart';
import 'authenticated_api_client.dart';
import 'hris_repository.dart';
import 'upload_image_url_resolver.dart';

class HomeDataException implements Exception {
  const HomeDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PersonalAttendanceDataException implements Exception {
  const PersonalAttendanceDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Keeps all Phase 3 feature data mocked while loading only the two approved
/// Home event feeds from the authenticated HRIS API.
class HybridHrisRepository implements HrisRepository {
  HybridHrisRepository({
    required HrisRepository mockRepository,
    required this.api,
    required this.imageUrls,
    DateTime Function()? clock,
  }) : _mock = mockRepository,
       _clock = clock ?? _nowInManila;

  final HrisRepository _mock;
  final AuthenticatedApiClient api;
  final UploadImageUrlResolver imageUrls;
  final DateTime Function() _clock;
  Future<List<Bulletin>>? _homeEvents;

  @override
  bool get isMock => false;

  @override
  bool get homeEventsAreLive => true;

  @override
  void invalidateHomeEvents() => _homeEvents = null;

  @override
  Future<List<Bulletin>> fetchBulletins() => _homeEvents ??= _loadHomeEvents();

  Future<List<Bulletin>> _loadHomeEvents() async {
    final today = _dateOnly(_clock());
    final start = today.subtract(const Duration(days: 7));
    final end = today.add(const Duration(days: 366));
    final query = {'startDate': _iso(start), 'endDate': _iso(end)};
    try {
      final responses = await Future.wait([
        api.get('/attendance/api/holiday', query: query),
        api.get('/attendance/api/suspensions', query: query),
      ]);
      return <Bulletin>[
        ..._parseByDate(
          responses[0].body,
          kind: BulletinKind.holiday,
          start: start,
          end: end,
        ),
        ..._parseByDate(
          responses[1].body,
          kind: BulletinKind.suspension,
          start: start,
          end: end,
        ),
      ];
    } on ProtectedApiException catch (error) {
      throw HomeDataException(error.message);
    } on FormatException {
      throw const HomeDataException(
        'HRIS returned invalid holiday or suspension data.',
      );
    }
  }

  List<Bulletin> _parseByDate(
    Map<String, Object?> body, {
    required BulletinKind kind,
    required DateTime start,
    required DateTime end,
  }) {
    if (body['success'] != true || body['byDate'] is! Map) {
      throw const FormatException('Invalid Home event envelope');
    }
    final grouped = <String, _EventGroup>{};
    final byDate = body['byDate'] as Map;
    for (final rawEntry in byDate.entries) {
      final date = _parseIsoDate(rawEntry.key);
      if (date == null || date.isBefore(start) || date.isAfter(end)) continue;
      final values = rawEntry.value is List
          ? rawEntry.value as List
          : <Object?>[rawEntry.value];
      for (final raw in values) {
        if (raw is! Map) continue;
        final event = raw.map((key, value) => MapEntry(key.toString(), value));
        if (!_isInstitutionWide(event, kind)) continue;
        final id = _nonEmpty(event['id']);
        final title = _nonEmpty(event['title']);
        if (id == null || title == null) continue;
        final imageUrl = imageUrls.resolve(event['image']);
        final key = '${kind.name}:$id';
        final existing = grouped[key];
        if (existing == null) {
          grouped[key] = _EventGroup(
            id: id,
            kind: kind,
            title: title,
            about: _nonEmpty(event['reason']),
            imageUrl: imageUrl,
            first: date,
            last: date,
          );
        } else {
          existing.imageUrl ??= imageUrl;
          if (date.isBefore(existing.first)) existing.first = date;
          if (date.isAfter(existing.last)) existing.last = date;
        }
      }
    }
    return grouped.values
        .map(
          (event) => Bulletin(
            id: event.id,
            kind: event.kind,
            title: event.title,
            about: event.about,
            imageUrl: event.imageUrl,
            start: event.first,
            end: event.last == event.first ? null : event.last,
          ),
        )
        .toList();
  }

  static bool _isInstitutionWide(
    Map<String, Object?> event,
    BulletinKind kind,
  ) {
    if (!event.containsKey('branch') || event['branch'] != null) return false;
    if (kind == BulletinKind.holiday) return true;
    return event['personnel_scope'] == 'all';
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static DateTime? _parseIsoDate(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final parts = value.split('-').map(int.parse).toList();
    final date = DateTime(parts[0], parts[1], parts[2]);
    if (date.year != parts[0] ||
        date.month != parts[1] ||
        date.day != parts[2]) {
      return null;
    }
    return date;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _nowInManila() =>
      DateTime.now().toUtc().add(const Duration(hours: 8));

  static String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  @override
  Future<Employee> fetchEmployee(String employeeNumber) =>
      _mock.fetchEmployee(employeeNumber);

  @override
  Future<List<AttendancePunch>> fetchPunches(
    String employeeNumber, {
    required DateTime start,
    required DateTime end,
  }) => _mock.fetchPunches(employeeNumber, start: start, end: end);

  @override
  Future<PersonalAttendancePage> fetchPersonalAttendance(
    PersonalAttendanceQuery query,
  ) async {
    try {
      final response = await api.post(
        '/attendance/api/me/attendance',
        body: query.toRequestBody(),
      );
      return PersonalAttendancePage.fromJson(response.body);
    } on ProtectedApiException catch (error) {
      throw PersonalAttendanceDataException(error.message);
    } on FormatException {
      throw const PersonalAttendanceDataException(
        'HRIS returned invalid personal attendance data.',
      );
    }
  }

  @override
  Future<OfficialTime?> fetchOfficialTime(
    String employeeNumber,
    DateTime date,
  ) => _mock.fetchOfficialTime(employeeNumber, date);

  @override
  Future<AttendanceMonth> fetchAttendanceMonth(
    String employeeNumber, {
    required int year,
    required int month,
  }) => _mock.fetchAttendanceMonth(employeeNumber, year: year, month: month);
}

class _EventGroup {
  _EventGroup({
    required this.id,
    required this.kind,
    required this.title,
    required this.about,
    required this.imageUrl,
    required this.first,
    required this.last,
  });

  final String id;
  final BulletinKind kind;
  final String title;
  final String? about;
  Uri? imageUrl;
  DateTime first;
  DateTime last;
}
