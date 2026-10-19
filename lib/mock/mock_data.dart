// MOCK DATA FOR UI DEVELOPMENT ONLY.
//
// Every person, number, office and record here is fictional. Nothing comes
// from the HRIS database; values only follow the shapes and formats of the
// real API so the screens can be built before backend integration (Phase 4).

import '../models/attendance.dart';
import '../models/bulletin.dart';
import '../models/employee.dart';
import '../utils/access_rules.dart';

/// A sample account for the mock sign-in picker.
class MockAccount {
  const MockAccount({required this.employee, required this.description});

  final Employee employee;

  /// What this account demonstrates.
  final String description;
}

const mockAccounts = <MockAccount>[
  MockAccount(
    description: 'Employee dashboard with today\'s punches',
    employee: Employee(
      employeeNumber: 'SAMPLE1001',
      role: UserRole.staff,
      pageAccess: {attendancePageId},
      firstName: 'Maria',
      middleName: 'Lopez',
      lastName: 'Reyes',
      email: 'maria.reyes@example.com',
      employmentCategory: 'Non-Academic · General Administration',
      departmentCode: 'SMPL-A',
      departmentName: 'Sample Office A',
    ),
  ),
  MockAccount(
    description: 'Job Order employee dashboard, no punches today',
    employee: Employee(
      employeeNumber: 'SAMPLE1002',
      role: UserRole.staff,
      pageAccess: {attendancePageId},
      firstName: 'Jose',
      lastName: 'Bautista',
      nameExtension: 'Jr.',
      email: 'jose.bautista@example.com',
      employmentCategory: 'Non-Academic · Job Order - Undergraduate',
      isJobOrder: true,
      // No department: the web header simply leaves it out.
    ),
  ),
  MockAccount(
    description: 'Admin dashboard, Attendance page granted',
    employee: Employee(
      employeeNumber: 'SAMPLE2001',
      role: UserRole.administrator,
      pageAccess: {attendancePageId},
      firstName: 'Ana',
      middleName: 'Cruz',
      lastName: 'Garcia',
      email: 'ana.garcia@example.com',
      employmentCategory: 'Academic - 40 Hours · Full Time',
      departmentCode: 'SMPL-B',
      departmentName: 'Sample Office B',
    ),
  ),
  MockAccount(
    description: 'Admin dashboard, no Attendance page access',
    employee: Employee(
      employeeNumber: 'SAMPLE2002',
      role: UserRole.administrator,
      firstName: 'Ramon',
      middleName: 'Diaz',
      lastName: 'Villanueva',
      email: 'ramon.villanueva@example.com',
      employmentCategory: 'Non-Academic · Contractual',
      departmentCode: 'SMPL-B',
      departmentName: 'Sample Office B',
    ),
  ),
  MockAccount(
    description: 'Admin dashboard, all pages (role bypass)',
    employee: Employee(
      employeeNumber: 'SAMPLE3001',
      role: UserRole.superadmin,
      firstName: 'Liza',
      lastName: 'Mendoza',
      email: 'liza.mendoza@example.com',
      employmentCategory: 'Non-Academic · General Administration',
      departmentCode: 'SMPL-C',
      departmentName: 'Sample Office C',
    ),
  ),
  MockAccount(
    description: 'Developer account, no attendance records',
    employee: Employee(
      employeeNumber: 'SAMPLE4001',
      role: UserRole.technical,
      firstName: 'Carlo',
      middleName: 'Ramos',
      lastName: 'Aquino',
      email: 'carlo.aquino@example.com',
      employmentCategory: 'Non-Academic · Research',
    ),
  ),
];

Employee? findMockEmployee(String employeeNumber) {
  final wanted = employeeNumber.trim().toUpperCase();
  for (final account in mockAccounts) {
    if (account.employee.employeeNumber == wanted) return account.employee;
  }
  return null;
}

const mockOfficialTime = OfficialTime(timeIn: '08:00:00', timeOut: '17:00:00');

/// Which sample accounts have an official time assigned.
const mockOfficialTimeAssigned = {'SAMPLE1001', 'SAMPLE2001', 'SAMPLE3001'};

/// Fictional device punches for the last 400 days up to [now], so month and
/// year filters (including the previous year) have sample data.
List<AttendancePunch> buildMockPunches(String employeeNumber, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final punches = <AttendancePunch>[];

  void add(
    DateTime day,
    int h,
    int m,
    int s,
    int state, {
    String? device = 'Main Gate',
    int? branch = 0,
  }) {
    final at = DateTime(day.year, day.month, day.day, h, m, s);
    if (at.isAfter(now)) return;
    punches.add(
      AttendancePunch(
        employeeNumber: employeeNumber,
        at: at,
        state: state,
        deviceName: device,
        branch: branch,
      ),
    );
  }

  void workday(DateTime day, {int inH = 7, int inM = 48}) {
    add(day, inH, inM, 12, 1);
    add(day, 12, 1, 40, 2, device: 'Back Gate');
    add(day, 12, 57, 5, 3, device: 'Back Gate');
    add(day, 17, 4, 31, 4);
  }

  final hasPunches = switch (employeeNumber) {
    'SAMPLE1001' || 'SAMPLE1002' || 'SAMPLE2001' || 'SAMPLE3001' => true,
    _ => false, // SAMPLE2002 and SAMPLE4001: empty-state demonstrations
  };
  if (!hasPunches) return punches;

  for (var offset = 400; offset >= 0; offset--) {
    final day = DateTime(today.year, today.month, today.day - offset);

    if (offset == 0) {
      // Today always has sample punches (even on a weekend) so the Home card
      // can be demonstrated; SAMPLE1002 has none ("No record yet").
      if (employeeNumber != 'SAMPLE1002') workday(day, inH: 7, inM: 52);
      continue;
    }
    if (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday) {
      continue;
    }

    switch (day.day % 6) {
      case 0:
        break; // no punches that day
      case 1:
        workday(day, inH: 8, inM: 17);
      case 2:
        add(day, 7, 41, 9, 1); // Time IN only
      default:
        workday(day);
    }

    if (employeeNumber == 'SAMPLE1001' && offset == 3) {
      // Punch at the other campus, and one with no device information.
      add(day, 18, 2, 7, 4, device: 'Main Lobby', branch: 1);
      add(day, 18, 30, 0, 0, device: null, branch: null); // Uncategorized
    }
  }
  return punches;
}

/// Fictional announcements, holidays and suspensions around [now]. One item
/// of each kind is old enough to be hidden by the carousel rules, and one
/// holiday is inactive.
List<Bulletin> buildMockBulletins(DateTime now) {
  DateTime d(int offset) => DateTime(now.year, now.month, now.day + offset);
  return [
    Bulletin(
      id: 'announcement-1',
      kind: BulletinKind.announcement,
      title: 'Sample: Office systems maintenance',
      about: 'Fictional announcement for testing the mobile Home carousel.',
      start: d(3),
      end: d(3),
    ),
    Bulletin(
      id: 'announcement-2',
      kind: BulletinKind.announcement,
      title: 'Sample: Updated office hours notice',
      about: 'Fictional announcement that started earlier and is still shown.',
      start: d(-4),
      end: d(10),
    ),
    Bulletin(
      id: 'holiday-1',
      kind: BulletinKind.holiday,
      title: 'Sample Holiday',
      about: 'Official holiday.',
      start: d(12),
      end: d(12),
    ),
    Bulletin(
      id: 'suspension-1',
      kind: BulletinKind.suspension,
      title: 'Sample: Work suspension (weather)',
      about: 'Fictional suspension for testing.',
      start: d(-2),
      end: d(-2),
    ),
    // Hidden: ended more than 7 days ago.
    Bulletin(
      id: 'announcement-old',
      kind: BulletinKind.announcement,
      title: 'Sample: Expired announcement',
      start: d(-30),
      end: d(-20),
    ),
    // Hidden: inactive holiday.
    Bulletin(
      id: 'holiday-inactive',
      kind: BulletinKind.holiday,
      title: 'Sample: Inactive holiday',
      start: d(5),
      end: d(5),
      active: false,
    ),
  ];
}

/// Fictional "My Attendance" day codes for one month, simulating what the
/// web derives from the DTR rules: weekends are non-working days, active
/// holidays and suspensions are "H", a punched day is "P" or "L" (late
/// against the 8:00 AM official time), an unpunched past workday is "A", and
/// regular employees have one sample leave day.
AttendanceMonth buildMockAttendanceMonth(
  String employeeNumber,
  int year,
  int month,
  DateTime now,
  bool isJobOrder,
) {
  final today = DateTime(now.year, now.month, now.day);
  final punches = buildMockPunches(employeeNumber, now);
  final bulletins = buildMockBulletins(now)
      .where((b) => b.kind != BulletinKind.announcement && b.active)
      .toList();
  final codes = <int, AttendanceCode>{};
  final names = <int, String>{};
  final suspensions = <int>{};
  final lastDay = DateTime(year, month + 1, 0).day;

  for (var day = 1; day <= lastDay; day++) {
    final date = DateTime(year, month, day);
    for (final b in bulletins) {
      final end = b.end ?? b.start;
      if (!date.isBefore(DateTime(b.start.year, b.start.month, b.start.day)) &&
          !date.isAfter(DateTime(end.year, end.month, end.day))) {
        names[day] = b.title;
        if (b.kind == BulletinKind.suspension) suspensions.add(day);
      }
    }
    if (names.containsKey(day)) {
      codes[day] = AttendanceCode.holiday;
      continue;
    }
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    final timeIn = punches
        .where((p) => p.day == date && p.state == 1)
        .map((p) => p.at)
        .fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    if (!isJobOrder && !weekend && date.day == 2 && date.isBefore(today)) {
      codes[day] = AttendanceCode.vacationLeave;
    } else if (timeIn != null) {
      final late = timeIn.hour > 8 || (timeIn.hour == 8 && timeIn.minute > 0);
      codes[day] = late ? AttendanceCode.late : AttendanceCode.present;
    } else if (weekend) {
      codes[day] = AttendanceCode.nonWorkingDay;
    } else if (date.isBefore(today) &&
        employeeNumber != 'SAMPLE4001' &&
        employeeNumber != 'SAMPLE2002') {
      codes[day] = AttendanceCode.absent;
    }
    // Otherwise blank: no punch recorded (not counted as absent).
  }

  return AttendanceMonth(
    year: year,
    month: month,
    codes: codes,
    holidayNames: names,
    suspensionDays: suspensions,
    officialTime: mockOfficialTimeAssigned.contains(employeeNumber)
        ? mockOfficialTime
        : null,
  );
}
