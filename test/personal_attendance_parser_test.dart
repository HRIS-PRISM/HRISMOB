import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/models/attendance.dart';

Map<String, Object?> record({
  Object? timestamp = 1792107000000,
  Object? state = 1,
  Object? branch = 0,
  Object? device = 'Main Gate',
  Object? personId = 'SELF-001',
}) => {
  'PersonID': personId,
  'Date': '10/15/2026',
  'Time': '8:30:00 AM',
  'AttendanceState': state,
  'AttendanceDateTime': timestamp,
  'DeviceName': ?device,
  'Branch': branch,
};

Map<String, Object?> page({
  List<Object?> data = const [],
  Object? total = 0,
  Object? currentPage = 1,
  Object? pageSize = 25,
}) => {'data': data, 'total': total, 'page': currentPage, 'pageSize': pageSize};

void main() {
  group('PersonalAttendancePage.fromJson', () {
    test('parses a valid paged response and preserves metadata', () {
      final result = PersonalAttendancePage.fromJson(
        page(data: [record()], total: 26, currentPage: 1, pageSize: 25),
      );

      expect(result.total, 26);
      expect(result.page, 1);
      expect(result.pageSize, 25);
      expect(result.hasMore, isTrue);
      expect(result.records.single.employeeNumber, 'SELF-001');
      expect(result.records.single.branch, 0);
      expect(result.records.single.deviceName, 'Main Gate');
    });

    test('accepts a valid empty page', () {
      final result = PersonalAttendancePage.fromJson(page());

      expect(result.records, isEmpty);
      expect(result.total, 0);
      expect(result.hasMore, isFalse);
    });

    test('parses multiple records and states 0 through 6', () {
      final result = PersonalAttendancePage.fromJson(
        page(
          data: [
            for (var state = 0; state <= 6; state++)
              record(timestamp: 1792107000000 + state, state: state),
          ],
          total: 7,
          pageSize: 25,
        ),
      );

      expect(result.records.map((punch) => punch.state), [0, 1, 2, 3, 4, 5, 6]);
    });

    test(
      'parses a numeric Unix millisecond timestamp as its original instant',
      () {
        final result = PersonalAttendancePage.fromJson(
          page(data: [record(timestamp: 1792107000000)], total: 1),
        );

        expect(
          result.records.single.at,
          DateTime.fromMillisecondsSinceEpoch(1792107000000, isUtc: true),
        );
      },
    );

    test('parses a UTC ISO timestamp as its original instant', () {
      final result = PersonalAttendancePage.fromJson(
        page(data: [record(timestamp: '2026-10-15T08:30:00.000Z')], total: 1),
      );

      expect(result.records.single.at, DateTime.utc(2026, 10, 15, 8, 30));
    });

    test('parses an offset ISO timestamp as its original instant', () {
      final result = PersonalAttendancePage.fromJson(
        page(data: [record(timestamp: '2026-10-15T16:30:00+08:00')], total: 1),
      );

      expect(result.records.single.at, DateTime.utc(2026, 10, 15, 8, 30));
    });

    test('accepts supported branch values and an omitted device name', () {
      final result = PersonalAttendancePage.fromJson(
        page(
          data: [
            record(branch: 0, device: null),
            record(timestamp: 1792107000001, branch: 1),
            record(timestamp: 1792107000002, branch: null, device: '  '),
          ],
          total: 3,
        ),
      );

      expect(result.records.map((punch) => punch.branch), [0, 1, null]);
      expect(result.records.first.deviceName, isNull);
      expect(result.records.last.deviceName, isNull);
    });

    test('rejects timezone-ambiguous and unsupported timestamps', () {
      for (final timestamp in [
        '2026-10-15T08:30:00',
        '2026-10-15 08:30:00Z',
        '2026-02-30T08:30:00Z',
        '2026-10-15T08:30:00+14:01',
        1792107000,
        1792107000000000,
        null,
      ]) {
        expect(
          () => PersonalAttendancePage.fromJson(
            page(data: [record(timestamp: timestamp)], total: 1),
          ),
          throwsFormatException,
        );
      }
    });

    test(
      'rejects missing timestamps, invalid states, and invalid branches',
      () {
        final invalidRecords = [
          {'PersonID': 'SELF-001', 'AttendanceState': 1, 'Branch': 0},
          record(state: '1'),
          record(branch: 2),
        ];
        for (final invalid in invalidRecords) {
          expect(
            () => PersonalAttendancePage.fromJson(
              page(data: [invalid], total: 1),
            ),
            throwsFormatException,
          );
        }
      },
    );

    test('rejects malformed records and pagination metadata', () {
      final invalidPages = [
        {'data': {}, 'total': 0, 'page': 1, 'pageSize': 25},
        page(data: [record()], total: -1),
        page(data: [record()], total: '1'),
        page(data: [record()], total: 1, currentPage: 0),
        page(data: [record()], total: 1, pageSize: 0),
        page(data: [record()], total: 1, pageSize: 201),
        page(data: List<Object?>.filled(2, record()), total: 2, pageSize: 1),
        page(data: [record()], total: 0),
      ];
      for (final invalid in invalidPages) {
        expect(
          () => PersonalAttendancePage.fromJson(invalid),
          throwsFormatException,
        );
      }
    });

    test('preserves unknown future integer states', () {
      final result = PersonalAttendancePage.fromJson(
        page(data: [record(state: 99)], total: 1),
      );

      expect(result.records.single.state, 99);
    });
  });
}
