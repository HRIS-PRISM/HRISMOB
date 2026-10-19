import 'package:intl/intl.dart';

/// Date and time formats matching the web HRIS.

/// Placeholder the web shows for an empty value.
const String emptyValue = '—';

final _punchTime = DateFormat('h:mm:ss a', 'en_US');
final _shortTime = DateFormat('h:mm a', 'en_US');
final _recordDate = DateFormat('EEE, MMM d, y', 'en_US');
final _todayDate = DateFormat('EEEE, MMM d', 'en_US');
final _isoDate = DateFormat('yyyy-MM-dd', 'en_US');
final _punchDate = DateFormat('M/d/yyyy', 'en_US');

/// "10/15/2026": the backend's en-PH punch `Date`, shown as-is in the web
/// record details.
String formatPunchDate(DateTime value) => _punchDate.format(value);

/// "8:05:12 AM": the backend's en-PH punch `Time`, which the web shows as-is.
String formatPunchTime(DateTime? value) =>
    value == null ? emptyValue : _punchTime.format(value);

/// "Thu, Oct 15, 2026" (AttendanceUserState.jsx `formatDateLabel`).
String formatRecordDate(DateTime value) => _recordDate.format(value);

/// "Thursday, Oct 15" (EmployeeHomeWidgets.jsx Today card).
String formatTodayDate(DateTime value) => _todayDate.format(value);

/// "2026-10-15" (period summary on the web Attendance page).
String formatIsoDate(DateTime value) => _isoDate.format(value);

/// Official time "HH:mm[:ss]" -> "8:00 AM" (EmployeeHomeWidgets.jsx `fmtTime`).
String formatOfficialTime(String? value) {
  if (value == null || value.isEmpty || value == '00:00:00' || value == '0') {
    return emptyValue;
  }
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(value);
  if (match == null) return value;
  return _shortTime.format(
    DateTime(2000, 1, 1, int.parse(match[1]!), int.parse(match[2]!)),
  );
}

/// The value, or the web placeholder when missing.
String orEmpty(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty) ? emptyValue : trimmed;
}
