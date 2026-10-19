import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../models/attendance.dart';
import '../models/employee.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/access_rules.dart';
import '../utils/attendance_rules.dart';
import '../utils/formatters.dart';
import '../widgets/attendance_widgets.dart';
import '../widgets/common.dart';
import '../widgets/greeting_header.dart';
import '../widgets/home_widgets.dart';

/// Home page for every role, adapted from the two web dashboards.
///
/// Web routing (Login.jsx): staff use `/home` (Home.jsx); superadmin,
/// administrator and technical use `/admin-home` (HomeAdmin.jsx).
///
/// - Both: greeting header and the announcements carousel.
/// - All roles (mobile requirement): the read-only "Today" card for the
///   signed-in employee. It does not grant the full Attendance page; its
///   "Attendance" link only appears when page access allows it.
/// - Staff: the "My Attendance" day strip; Job Orders instead get Time Logs,
///   Up Next and the attendance calendar, as in Home.jsx.
///
/// Leave, payslip, DTR, notes/events, notifications and the admin
/// dashboard's organisation-wide panels are outside the mobile scope.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.employee,
    required this.onOpenAttendance,
  });

  final Employee employee;
  final VoidCallback? onOpenAttendance;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _TodayData {
  const _TodayData(this.summary, this.officialTime);
  final TodaySummary summary;
  final OfficialTime? officialTime;
}

class _DashboardScreenState extends State<DashboardScreen> {
  Future<_TodayData>? _today;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_today == null) {
      // A new dashboard represents a new signed-in shell. Never reuse Home
      // event data (or an error future) from an earlier session.
      AppScope.of(context).repository.invalidateHomeEvents();
      _today = _load();
    }
  }

  Future<_TodayData> _load() async {
    final repo = AppScope.of(context).repository;
    final emp = widget.employee.employeeNumber;
    final now = DateTime.now();
    final results = await Future.wait([
      repo.fetchPunches(emp, start: now, end: now),
      repo.fetchOfficialTime(emp, now),
    ]);
    return _TodayData(
      summarizeToday(results[0] as List<AttendancePunch>),
      results[1] as OfficialTime?,
    );
  }

  int _generation = 0;

  Future<void> _refresh() async {
    AppScope.of(context).repository.invalidateHomeEvents();
    final next = _load();
    setState(() {
      _today = next;
      _generation++;
    });
    try {
      await next;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMock = AppScope.of(context).repository.isMock;
    final homeEventsAreLive = AppScope.of(context).repository.homeEventsAreLive;
    final employee = widget.employee;
    final isAdminDashboard = dashboardFor(employee.role) == DashboardKind.admin;
    final gap = SizedBox(height: Responsive.sectionGap(context));
    // New key per refresh so every section reloads its data.
    Key k(String name) => ValueKey('$name-$_generation');

    final todayCard = FutureBuilder<_TodayData>(
      future: _today,
      builder: (context, snapshot) => _TodayCard(
        snapshot: snapshot,
        onOpenAttendance: widget.onOpenAttendance,
        onRetry: _refresh,
      ),
    );

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: Responsive.pagePadding(
          context,
          top: Responsive.gutter(context),
          bottom: AppSpacing.xl,
        ),
        children: [
          if (isMock) ...[
            const MockNotice(
              message: 'Sample data only. Not connected to the HRIS.',
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (homeEventsAreLive) ...[
            const MockNotice(
              message:
                  'Holidays and suspensions are live. Attendance and Profile '
                  'still use sample data. Announcements are unavailable.',
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          GreetingHeader(employee: employee),
          gap,
          // Both web dashboards show the announcements carousel; they word
          // its empty state differently.
          BulletinCarousel(
            key: k('carousel'),
            emptyText: homeEventsAreLive
                ? 'No holidays or suspensions currently available.'
                : isAdminDashboard
                ? 'No announcements is currently available.'
                : 'No announcements currently available.',
            liveEvents: homeEventsAreLive,
            onRetry: _refresh,
          ),
          gap,
          // Mobile requirement: every role sees its own Today card.
          todayCard,
          if (!isAdminDashboard && employee.isJobOrder) ...[
            // Home.jsx, Job Orders: Time Logs, Up Next and the attendance
            // calendar without leave codes.
            gap,
            TimeLogsCard(
              key: k('timelogs'),
              employee: employee,
              onViewAll: widget.onOpenAttendance,
            ),
            gap,
            UpNextCard(
              key: k('upnext'),
              liveEvents: homeEventsAreLive,
              onRetry: _refresh,
            ),
            gap,
            MyAttendanceCard(
              key: k('myattendance'),
              employee: employee,
              calendar: true,
              hideLeave: true,
            ),
          ] else if (!isAdminDashboard) ...[
            // Home.jsx, other staff: the "My Attendance" day strip.
            gap,
            MyAttendanceCard(key: k('myattendance'), employee: employee),
          ],
          // Web "General Panel" is the sidebar menu: on mobile its items
          // are the bottom navigation (or rail), not a Home card.
          if (isAdminDashboard) ...[
            gap,
            const Text(
              'Administration panels are available in the web HRIS only.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Web `EmployeeTodayCard` (EmployeeHomeWidgets.jsx), including its labels.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.snapshot,
    required this.onOpenAttendance,
    required this.onRetry,
  });

  final AsyncSnapshot<_TodayData> snapshot;
  final VoidCallback? onOpenAttendance;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (snapshot.hasError) {
      content = MessageView(
        icon: Icons.error_outline,
        title: 'Failed to load attendance data. Please try again.',
        color: AppColors.errorFg,
        action: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh'),
        ),
      );
    } else if (!snapshot.hasData) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
      );
    } else {
      final data = snapshot.data!;
      final s = data.summary;
      final ot = data.officialTime;
      final official = (ot != null && ot.isAssigned)
          ? '${formatOfficialTime(ot.timeIn)} – ${formatOfficialTime(ot.timeOut)}'
          : 'No official time assigned';
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatTodayDate(DateTime.now()),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.muted,
                  ),
                ),
              ),
              TodayStatusPill(status: s.status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Same order and wording as the web card.
          _Grid(
            children: [
              ValueTile(label: 'Time in', value: formatPunchTime(s.timeIn)),
              ValueTile(
                label: 'Breaktime in',
                value: formatPunchTime(s.breaktimeIn),
              ),
              ValueTile(
                label: 'Breaktime out',
                value: formatPunchTime(s.breaktimeOut),
              ),
              ValueTile(label: 'Time out', value: formatPunchTime(s.timeOut)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ValueTile(
            label: 'Official time',
            value: official,
            labelColor: AppColors.accent,
            background: AppColors.accentFaint,
            borderColor: AppColors.accentBorder,
          ),
        ],
      );
    }

    return SectionCard(
      title: 'Today',
      icon: Icons.access_time,
      trailing: onOpenAttendance == null
          ? null
          : TextButton(
              onPressed: onOpenAttendance,
              child: const Text('Attendance'),
            ),
      child: content,
    );
  }
}

/// Time tiles: four across on wide screens, two across on phones, and one
/// per row when large system text leaves a tile too narrow for its time.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final minTile = 132 * Responsive.textScale(context);
    // Two across down to the narrowest phones; long times shrink to fit
    // (ValueTile) rather than stacking four tall tiles.
    const minPair = 112.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSpacing.sm;
        final width = constraints.maxWidth;
        final columns = width >= 4 * minTile + 3 * gap
            ? 4
            : width >= 2 * minPair + gap
            ? 2
            : 1;
        final rows = <Widget>[];
        for (var i = 0; i < children.length; i += columns) {
          if (i > 0) rows.add(const SizedBox(height: gap));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  Expanded(
                    child: i + c < children.length
                        ? children[i + c]
                        : const SizedBox(),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}
