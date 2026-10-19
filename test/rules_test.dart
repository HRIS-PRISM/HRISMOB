import 'package:flutter_test/flutter_test.dart';
import 'package:hrismob/mock/mock_data.dart';
import 'package:hrismob/models/attendance.dart';
import 'package:hrismob/models/bulletin.dart';
import 'package:hrismob/utils/home_rules.dart';
import 'package:hrismob/models/employee.dart';
import 'package:hrismob/utils/access_rules.dart';
import 'package:hrismob/utils/attendance_rules.dart';
import 'package:hrismob/utils/formatters.dart';

AttendancePunch punch(int h, int m, int state) => AttendancePunch(
  employeeNumber: 'T1',
  at: DateTime(2026, 10, 15, h, m),
  state: state,
);

Employee employee(UserRole role, {Set<String> access = const {}}) =>
    Employee(employeeNumber: 'T1', role: role, pageAccess: access);

void main() {
  group('punch status labels (AttendanceUserState.jsx)', () {
    test('known codes', () {
      expect(punchStatusLabel(1), 'Time In');
      expect(punchStatusLabel(2), 'Breaktime Out');
      expect(punchStatusLabel(3), 'Breaktime In');
      expect(punchStatusLabel(4), 'Time Out');
    });
    test('uncategorized and special codes have distinct labels', () {
      expect(punchStatusLabel(0), 'Uncategorized');
      expect(punchStatusLabel(5), 'Special Time In');
      expect(punchStatusLabel(6), 'Special Time Out');
    });
    test('unknown codes retain their value in a safe fallback label', () {
      expect(punchStatusLabel(9), 'Unknown state (9)');
    });
    test('branch labels', () {
      expect(branchLabel(0), 'Manila');
      expect(branchLabel(1), 'Cavite');
      expect(branchLabel(null), 'Unknown');
    });
  });

  group('Today card (EmployeeHomeWidgets.jsx)', () {
    test('no punches -> No record yet', () {
      expect(summarizeToday([]).status.label, 'No record yet');
    });
    test('break punches without Time in -> No record yet', () {
      expect(summarizeToday([punch(12, 0, 2)]).status, TodayStatus.noRecordYet);
    });
    test('Time in only -> Clocked in', () {
      expect(summarizeToday([punch(7, 50, 1)]).status.label, 'Clocked in');
    });
    test('Time in and Time out -> Complete', () {
      final s = summarizeToday([punch(7, 50, 1), punch(17, 5, 4)]);
      expect(s.status.label, 'Complete');
    });
    test('first Time in / Breaktime out, latest Breaktime in / Time out', () {
      final s = summarizeToday([
        punch(8, 10, 1),
        punch(7, 50, 1),
        punch(12, 0, 2),
        punch(12, 5, 2),
        punch(12, 50, 3),
        punch(12, 58, 3),
        punch(17, 0, 4),
        punch(17, 30, 4),
      ]);
      expect(s.timeIn, DateTime(2026, 10, 15, 7, 50));
      expect(s.breaktimeOut, DateTime(2026, 10, 15, 12, 0));
      expect(s.breaktimeIn, DateTime(2026, 10, 15, 12, 58));
      expect(s.timeOut, DateTime(2026, 10, 15, 17, 30));
    });
  });

  group('quick periods (attendanceFilterLayout.jsx)', () {
    final now = DateTime(2026, 10, 15, 9, 30);
    test('Today and Yesterday', () {
      expect(QuickPeriod.today.range(now).start, DateTime(2026, 10, 15));
      expect(QuickPeriod.yesterday.range(now).start, DateTime(2026, 10, 14));
      expect(QuickPeriod.yesterday.range(now).end, DateTime(2026, 10, 14));
    });
    test('Last 7/15 Days start 7/15 days before today', () {
      expect(QuickPeriod.last7.range(now).start, DateTime(2026, 10, 8));
      expect(QuickPeriod.last15.range(now).start, DateTime(2026, 9, 30));
    });
    test('Last 30 Days goes back one calendar month, rolling over like JS', () {
      expect(QuickPeriod.last30.range(now).start, DateTime(2026, 9, 15));
      expect(QuickPeriod.last30.range(now).end, DateTime(2026, 10, 15));
      // JS: new Date('2026-03-31').setMonth(1) -> Feb 31 -> Mar 3.
      expect(
        QuickPeriod.last30.range(DateTime(2026, 3, 31)).start,
        DateTime(2026, 3, 3),
      );
      // Year boundary.
      expect(
        QuickPeriod.last30.range(DateTime(2027, 1, 10)).start,
        DateTime(2026, 12, 10),
      );
    });
  });

  group('month picker (AttendanceUserState.jsx handleMonthClick)', () {
    test('month range is the first to the last day', () {
      final oct = monthRange(2026, 9);
      expect(oct.start, DateTime(2026, 10, 1));
      expect(oct.end, DateTime(2026, 10, 31));
    });
    test('December ends on Dec 31 of the same year', () {
      final dec = monthRange(2026, 11);
      expect(dec.start, DateTime(2026, 12, 1));
      expect(dec.end, DateTime(2026, 12, 31));
    });
    test('February respects leap years', () {
      expect(monthRange(2028, 1).end, DateTime(2028, 2, 29));
      expect(monthRange(2026, 1).end, DateTime(2026, 2, 28));
    });
    test('year options: five years either side', () {
      final years = yearOptions(DateTime(2026, 10, 15));
      expect(years.first, 2021);
      expect(years.last, 2031);
      expect(years.length, 11);
    });
    test('month labels', () {
      expect(monthsShort.first, 'JAN');
      expect(monthsShort.last, 'DEC');
      expect(monthsShort.length, 12);
    });
    test('newest first by default order', () {
      final sorted = sortPunches([
        punch(7, 0, 1),
        punch(17, 0, 4),
      ], SortOrder.newestFirst);
      expect(sorted.first.state, 4);
    });
  });

  group('roles and page access (Login.jsx, Sidebar.jsx)', () {
    test('only staff get the employee dashboard', () {
      expect(dashboardFor(UserRole.staff), DashboardKind.employee);
      expect(dashboardFor(UserRole.administrator), DashboardKind.admin);
      expect(dashboardFor(UserRole.superadmin), DashboardKind.admin);
      expect(dashboardFor(UserRole.technical), DashboardKind.admin);
    });
    test('superadmin and technical bypass page access', () {
      expect(canSeeAttendance(employee(UserRole.superadmin)), isTrue);
      expect(canSeeAttendance(employee(UserRole.technical)), isTrue);
    });
    test('staff and administrator need the page grant', () {
      expect(canSeeAttendance(employee(UserRole.staff)), isFalse);
      expect(canSeeAttendance(employee(UserRole.administrator)), isFalse);
      expect(
        canSeeAttendance(
          employee(UserRole.administrator, access: {attendancePageId}),
        ),
        isTrue,
      );
    });
    test('roles parse from database values only', () {
      expect(UserRole.fromValue('Administrator'), UserRole.administrator);
      expect(UserRole.fromValue('admin'), isNull);
    });
  });

  group('formatters', () {
    test('punch time and record date match the web format', () {
      final t = DateTime(2026, 10, 15, 13, 30, 5);
      expect(formatPunchTime(t), '1:30:05 PM');
      expect(formatRecordDate(t), 'Thu, Oct 15, 2026');
      expect(formatTodayDate(t), 'Thursday, Oct 15');
      expect(formatPunchDate(t), '10/15/2026');
      expect(formatIsoDate(t), '2026-10-15');
    });
    test('official time and empty values', () {
      expect(formatOfficialTime('08:00:00'), '8:00 AM');
      expect(formatOfficialTime('17:00:00'), '5:00 PM');
      expect(formatOfficialTime(null), '—');
      expect(orEmpty('  '), '—');
    });
  });

  group('mock data', () {
    test('every sample account is fictional and one per case', () {
      final numbers = mockAccounts
          .map((a) => a.employee.employeeNumber)
          .toSet();
      expect(numbers.length, mockAccounts.length);
      expect(numbers.every((n) => n.startsWith('SAMPLE')), isTrue);
      expect(
        mockAccounts.every((a) => a.employee.email!.endsWith('@example.com')),
        isTrue,
      );
      expect(
        mockAccounts.map((a) => a.employee.role).toSet(),
        UserRole.values.toSet(),
      );
    });
    test('punches belong only to the requested employee', () {
      final now = DateTime(2026, 10, 15, 21);
      final punches = buildMockPunches('SAMPLE1001', now);
      expect(punches, isNotEmpty);
      expect(punches.every((p) => p.employeeNumber == 'SAMPLE1001'), isTrue);
      expect(punches.every((p) => !p.at.isAfter(now)), isTrue);
      expect(buildMockPunches('SAMPLE4001', now), isEmpty);
    });
  });

  group('Home rules (Home.jsx, carouselVisibility.js)', () {
    final now = DateTime(2026, 10, 15, 9);
    Bulletin b(
      String id,
      BulletinKind kind,
      DateTime start, {
      DateTime? end,
      bool active = true,
    }) => Bulletin(
      id: id,
      kind: kind,
      title: id,
      start: start,
      end: end,
      active: active,
    );

    test('items stay visible 7 days after their end date', () {
      expect(isStillShowing(DateTime(2026, 10, 8), now), isTrue);
      expect(isStillShowing(DateTime(2026, 10, 7), now), isFalse);
      expect(isStillShowing(null, now), isTrue);
    });

    test('carousel: active unexpired items, newest first', () {
      final items = carouselItems([
        b(
          'old',
          BulletinKind.announcement,
          DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 2),
        ),
        b('a', BulletinKind.announcement, DateTime(2026, 10, 18)),
        b(
          'h',
          BulletinKind.holiday,
          DateTime(2026, 10, 27),
          end: DateTime(2026, 10, 27),
        ),
        b('off', BulletinKind.holiday, DateTime(2026, 10, 20), active: false),
        b(
          's',
          BulletinKind.suspension,
          DateTime(2026, 10, 13),
          end: DateTime(2026, 10, 13),
        ),
      ], now);
      expect(items.map((i) => i.id), ['h', 'a', 's']);
    });

    test('Up Next: upcoming only, soonest first, Today/Tomorrow/in Nd', () {
      final items = upNextItems([
        b('later', BulletinKind.announcement, DateTime(2026, 10, 20)),
        b(
          'tomorrow',
          BulletinKind.holiday,
          DateTime(2026, 10, 16),
          end: DateTime(2026, 10, 16),
        ),
        b(
          'ongoing',
          BulletinKind.suspension,
          DateTime(2026, 10, 14),
          end: DateTime(2026, 10, 15),
        ),
        b('past', BulletinKind.announcement, DateTime(2026, 10, 10)),
      ], now);
      expect(items.map((i) => i.bulletin.id), ['ongoing', 'tomorrow', 'later']);
      expect(items.map((i) => i.when), ['Today', 'Tomorrow', 'in 5d']);
    });

    test('Up Next keeps at most 8 items', () {
      final many = [
        for (var i = 0; i < 12; i++)
          b('a$i', BulletinKind.announcement, DateTime(2026, 10, 16 + i)),
      ];
      expect(upNextItems(many, now).length, 8);
    });
  });
}
