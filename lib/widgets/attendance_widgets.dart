import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/attendance_rules.dart';
import 'common.dart';

/// Punch status pill (AttendanceUserState.jsx `StatusChip`).
class PunchStatusChip extends StatelessWidget {
  const PunchStatusChip({super.key, required this.state});

  final int state;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (state) {
      1 || 4 => (AppColors.punchInOut, Icons.check_circle),
      2 || 3 => (AppColors.punchBreak, Icons.access_time),
      _ => (AppColors.punchUnknown, Icons.cancel),
    };
    return StatusPill(label: punchStatusLabel(state), color: color, icon: icon);
  }
}

/// Campus pill (AttendanceBranchSource.jsx).
class BranchChip extends StatelessWidget {
  const BranchChip({super.key, required this.branch});

  final int? branch;

  @override
  Widget build(BuildContext context) {
    final color = switch (branch) {
      0 => AppColors.branchManila,
      1 => AppColors.branchCavite,
      _ => AppColors.branchUnknown,
    };
    return StatusPill(
      label: branchLabel(branch),
      color: color,
      icon: Icons.place,
    );
  }
}

/// Today status pill (EmployeeHomeWidgets.jsx `statusColor`).
class TodayStatusPill extends StatelessWidget {
  const TodayStatusPill({super.key, required this.status});

  final TodayStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      TodayStatus.complete => AppColors.complete,
      TodayStatus.clockedIn => AppColors.clockedIn,
      TodayStatus.noRecordYet => AppColors.accent,
    };
    return StatusPill(label: status.label, color: color);
  }
}
