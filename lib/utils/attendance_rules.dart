import '../models/attendance.dart';

/// Attendance display rules ported from the web HRIS. The backend has no
/// attendance-status endpoint; the web app derives these in the browser.

// ── Punch status: ATTENDANCE/AttendanceUserState.jsx `getAttendanceLabel` ──

String punchStatusLabel(int state) => switch (state) {
  0 => 'Uncategorized',
  1 => 'Time In',
  2 => 'Breaktime Out',
  3 => 'Breaktime In',
  4 => 'Time Out',
  5 => 'Special Time In',
  6 => 'Special Time Out',
  _ => 'Unknown state ($state)',
};

/// Web `punchBranchLabel` (users.branch codes: 0 = Manila, 1 = Cavite).
String branchLabel(int? branch) => switch (branch) {
  0 => 'Manila',
  1 => 'Cavite',
  _ => 'Unknown',
};

/// Web `punchSourceText`: "Manila · Back Gate", or just the branch.
String punchSourceText(AttendancePunch punch) {
  final device = punch.deviceName?.trim() ?? '';
  final branch = branchLabel(punch.branch);
  return device.isEmpty ? branch : '$branch · $device';
}

// ── Home "Today" card: EmployeeHomeWidgets.jsx `EmployeeTodayCard` ──

enum TodayStatus {
  noRecordYet('No record yet'),
  clockedIn('Clocked in'),
  complete('Complete');

  const TodayStatus(this.label);
  final String label;
}

class TodaySummary {
  const TodaySummary({
    required this.status,
    this.timeIn,
    this.breaktimeIn,
    this.breaktimeOut,
    this.timeOut,
  });

  final TodayStatus status;

  /// First state-1 punch ("Time in").
  final DateTime? timeIn;

  /// Latest state-3 punch, shown as "Breaktime in".
  final DateTime? breaktimeIn;

  /// First state-2 punch, shown as "Breaktime out".
  final DateTime? breaktimeOut;

  /// Latest state-4 punch ("Time out").
  final DateTime? timeOut;
}

/// Same selection and status rules as the web Today card:
/// no Time in -> "No record yet"; Time out present -> "Complete";
/// otherwise "Clocked in".
TodaySummary summarizeToday(Iterable<AttendancePunch> todaysPunches) {
  final ordered = [...todaysPunches]..sort((a, b) => a.at.compareTo(b.at));
  DateTime? first(int state) {
    for (final p in ordered) {
      if (p.state == state) return p.at;
    }
    return null;
  }

  DateTime? latest(int state) {
    for (final p in ordered.reversed) {
      if (p.state == state) return p.at;
    }
    return null;
  }

  final timeIn = first(1);
  final timeOut = latest(4);
  final status = timeIn == null
      ? TodayStatus.noRecordYet
      : (timeOut != null ? TodayStatus.complete : TodayStatus.clockedIn);

  return TodaySummary(
    status: status,
    timeIn: timeIn,
    breaktimeIn: latest(3),
    breaktimeOut: first(2),
    timeOut: timeOut,
  );
}

// ── Period filter: ATTENDANCE/attendanceFilterLayout.jsx and
//    ATTENDANCE/AttendanceUserState.jsx ──

typedef DateRange = ({DateTime start, DateTime end});

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Web default period: today → today.
DateRange todayRange(DateTime now) =>
    (start: dateOnly(now), end: dateOnly(now));

/// Web `QUICK_DATE_OPTIONS`.
enum QuickPeriod {
  today('Today'),
  yesterday('Yesterday'),
  last7('Last 7 Days'),
  last15('Last 15 Days'),
  last30('Last 30 Days');

  const QuickPeriod(this.label);
  final String label;

  /// Web `applyQuickDateRange`: "Last 7/15 Days" start 7/15 days before
  /// today; "Last 30 Days" starts one calendar month before today
  /// (`setMonth(month - 1)`, which rolls over like Dart's DateTime). All end
  /// today. Dates are local (Asia/Manila) days.
  DateRange range(DateTime now) {
    final today = dateOnly(now);
    DateTime back(int days) =>
        DateTime(today.year, today.month, today.day - days);
    return switch (this) {
      QuickPeriod.today => (start: today, end: today),
      QuickPeriod.yesterday => (start: back(1), end: back(1)),
      QuickPeriod.last7 => (start: back(7), end: today),
      QuickPeriod.last15 => (start: back(15), end: today),
      QuickPeriod.last30 => (
        start: DateTime(today.year, today.month - 1, today.day),
        end: today,
      ),
    };
  }
}

/// Web `MONTHS_SHORT` (month grid labels).
const monthsShort = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// Web `yearOptions`: five years before through five years after this year.
List<int> yearOptions(DateTime now) =>
    List.generate(11, (i) => now.year - 5 + i);

/// Web `handleMonthClick`: the first through the last day of the month
/// ([monthIndex] is 0-based, as in the web).
DateRange monthRange(int year, int monthIndex) => (
  start: DateTime(year, monthIndex + 1, 1),
  end: DateTime(year, monthIndex + 2, 0),
);

/// Web default sort is `desc` ("Newest First").
enum SortOrder {
  newestFirst('Newest First'),
  oldestFirst('Oldest First');

  const SortOrder(this.label);
  final String label;
}

List<AttendancePunch> sortPunches(
  Iterable<AttendancePunch> punches,
  SortOrder order,
) {
  final list = [...punches]..sort((a, b) => a.at.compareTo(b.at));
  return order == SortOrder.newestFirst ? list.reversed.toList() : list;
}
