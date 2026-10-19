/// One raw biometric device punch.
///
/// Mock fixtures use a local wall-clock [at]. Parsed personal-attendance
/// responses retain the source instant in UTC so a later UI integration can
/// deliberately convert it to the Asia/Manila display calendar.
class AttendancePunch {
  const AttendancePunch({
    required this.employeeNumber,
    required this.at,
    required this.state,
    this.deviceName,
    this.branch,
  });

  final String employeeNumber;

  /// The punch instant. Parsed API values are UTC; mock fixtures are local.
  final DateTime at;

  /// Device `AttendanceState` code. Known values are 0 through 6; unknown
  /// future values are deliberately preserved rather than coerced.
  final int state;

  final String? deviceName;

  /// Campus code: 0 = Manila, 1 = Cavite, null = unknown.
  final int? branch;

  DateTime get day => DateTime(at.year, at.month, at.day);
}

/// One validated page from `POST /attendance/api/me/attendance`.
///
/// This is a response-only model. It intentionally has no employee selector:
/// the backend derives the employee from the authenticated session.
class PersonalAttendancePage {
  const PersonalAttendancePage({
    required this.records,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<AttendancePunch> records;
  final int total;
  final int page;
  final int pageSize;

  bool get hasMore => page * pageSize < total;

  factory PersonalAttendancePage.fromJson(Map<String, Object?> json) {
    final rawRecords = json['data'];
    if (rawRecords is! List) {
      throw const FormatException('Invalid personal attendance data');
    }

    final total = _positiveOrZeroInt(json['total'], 'total');
    final page = _positiveInt(json['page'], 'page');
    final pageSize = _positiveInt(json['pageSize'], 'pageSize');
    if (pageSize > 200) {
      throw const FormatException('Invalid personal attendance pageSize');
    }
    if (rawRecords.length > pageSize || total < rawRecords.length) {
      throw const FormatException('Inconsistent personal attendance page');
    }

    final records = <AttendancePunch>[
      for (final raw in rawRecords)
        _parseRecord(_object(raw, 'personal attendance record')),
    ];
    return PersonalAttendancePage(
      records: List.unmodifiable(records),
      total: total,
      page: page,
      pageSize: pageSize,
    );
  }

  static AttendancePunch _parseRecord(Map<String, Object?> json) {
    final rawState = json['AttendanceState'];
    if (rawState is! int) {
      throw const FormatException('Invalid attendance state');
    }

    final rawBranch = json['Branch'];
    if (rawBranch != null && rawBranch is! int) {
      throw const FormatException('Invalid attendance branch');
    }
    if (rawBranch != null && rawBranch != 0 && rawBranch != 1) {
      throw const FormatException('Unsupported attendance branch');
    }

    final rawDevice = json['DeviceName'];
    if (rawDevice != null && rawDevice is! String) {
      throw const FormatException('Invalid attendance device name');
    }
    final device = rawDevice == null ? null : (rawDevice as String).trim();

    return AttendancePunch(
      // This is response data only. It is never used as an API selector.
      employeeNumber: _identifier(json['PersonID']),
      at: _timestamp(json['AttendanceDateTime']),
      state: rawState,
      deviceName: device == null || device.isEmpty ? null : device,
      branch: rawBranch as int?,
    );
  }

  static Map<String, Object?> _object(Object? value, String description) {
    if (value is! Map) throw FormatException('Invalid $description');
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }

  static int _positiveOrZeroInt(Object? value, String field) {
    if (value is! int || value < 0) {
      throw FormatException('Invalid personal attendance $field');
    }
    return value;
  }

  static int _positiveInt(Object? value, String field) {
    if (value is! int || value < 1) {
      throw FormatException('Invalid personal attendance $field');
    }
    return value;
  }

  static String _identifier(Object? value) {
    if (value is! String && value is! num) {
      throw const FormatException('Invalid attendance employee identifier');
    }
    final identifier = value.toString().trim();
    if (identifier.isEmpty) {
      throw const FormatException('Invalid attendance employee identifier');
    }
    return identifier;
  }

  static DateTime _timestamp(Object? value) {
    if (value is int) {
      // Twelve to fourteen digits distinguish supported Unix milliseconds
      // from common seconds and microseconds representations.
      if (value < 100000000000 || value > 99999999999999) {
        throw const FormatException('Unsupported attendance timestamp');
      }
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is! String) {
      throw const FormatException('Invalid attendance timestamp');
    }

    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(value);
    if (match == null || !_validIsoComponents(match)) {
      throw const FormatException('Invalid attendance timestamp');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('Invalid attendance timestamp');
    }
    return parsed.toUtc();
  }

  static bool _validIsoComponents(RegExpMatch match) {
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.parse(match[4]!);
    final minute = int.parse(match[5]!);
    final second = int.parse(match[6]!);
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      return false;
    }
    final zone = match[7]!;
    if (zone != 'Z') {
      final offsetHour = int.parse(zone.substring(1, 3));
      final offsetMinute = int.parse(zone.substring(4, 6));
      if (offsetHour > 14 ||
          offsetMinute > 59 ||
          (offsetHour == 14 && offsetMinute != 0)) {
        return false;
      }
    }
    final date = DateTime.utc(year, month, day);
    return date.year == year && date.month == month && date.day == day;
  }
}

/// Official schedule for a day (`officialtime` table, "HH:mm:ss" strings).
class OfficialTime {
  const OfficialTime({this.timeIn, this.timeOut});

  final String? timeIn;
  final String? timeOut;

  bool get isAssigned =>
      (timeIn?.isNotEmpty ?? false) || (timeOut?.isNotEmpty ?? false);
}

/// Day codes of the web "My Attendance" widget (AttendanceCalendar.jsx
/// `CHIPS`), in the web's display order.
enum AttendanceCode {
  present('P', 'Present'),
  absent('A', 'Absent'),
  vacationLeave('VL', 'Vacation leave'),
  sickLeave('SL', 'Sick leave'),
  nonWorkingDay('NWD', 'Non-working day'),
  holiday('H', 'Holiday'),
  late('L', 'Late');

  const AttendanceCode(this.code, this.label);
  final String code;
  final String label;

  bool get isLeave => this == vacationLeave || this == sickLeave;
}

/// One month of the "My Attendance" widget for the signed-in employee.
///
/// The web derives each day's code in the browser from four sources (DTR
/// attendance rows, leave/suspension/holiday maps, computed late totals and
/// Official Time). A blank day (no entry) means no punch was recorded and is
/// not counted as absent.
class AttendanceMonth {
  const AttendanceMonth({
    required this.year,
    required this.month,
    required this.codes,
    this.holidayNames = const {},
    this.suspensionDays = const {},
    this.officialTime,
  });

  final int year;

  /// 1–12.
  final int month;

  /// Day of month -> code.
  final Map<int, AttendanceCode> codes;

  /// Day of month -> holiday or suspension name (calendar view).
  final Map<int, String> holidayNames;

  /// Days in [holidayNames] that are suspensions rather than holidays.
  final Set<int> suspensionDays;

  final OfficialTime? officialTime;

  int count(AttendanceCode code) => codes.values.where((c) => c == code).length;
}
