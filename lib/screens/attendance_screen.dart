import 'dart:math' as math;

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

/// Read-only list of the employee's own device punches: the web General
/// "Attendance" page (ATTENDANCE/AttendanceUserState.jsx, "My Attendance
/// Records"), adapted for phones. No attendance can be added or changed.
///
/// The filter has every web control (Year, Quick Dates, the JAN–DEC month
/// grid, From/To, Clear) in a compact panel that starts collapsed. Unlike the
/// web, where each control applies at once, choices here are a draft until
/// **Search** is tapped (mobile requirement); Search then collapses the panel
/// and scrolls to the results. Clear and "Back to today" return to today and
/// apply immediately, as on the web.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    required this.employee,
    required this.onReturnHome,
    this.clock = DateTime.now,
  });

  final Employee employee;
  final VoidCallback onReturnHome;

  /// Source of "today" (injectable for tests).
  final DateTime Function() clock;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  // Applied criteria (web default: today → today).
  late DateRange _range;

  // Draft criteria, applied by Search.
  late DateRange _draft;
  late int _year; // web default: this year
  int? _month; // 0-based draft month highlight

  SortOrder _sort = SortOrder.newestFirst; // web default: 'desc'
  bool _filterOpen = false;
  Future<List<AttendancePunch>>? _records;
  int? _expanded;

  final _scroll = ScrollController();
  final _resultsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final now = widget.clock();
    _range = todayRange(now);
    _draft = _range;
    _year = now.year;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_records == null && canSeeAttendance(widget.employee)) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _load() {
    _expanded = null;
    _records = AppScope.of(context).repository.fetchPunches(
      widget.employee.employeeNumber,
      start: _range.start,
      end: _range.end,
    );
  }

  bool get _draftChanged =>
      _draft.start != _range.start || _draft.end != _range.end;

  /// Applies the draft, collapses the filter and scrolls to the results.
  void _search() {
    setState(() {
      _range = _draft;
      _filterOpen = false;
      _load();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _resultsKey.currentContext;
      if (target != null && mounted) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Web `resetToToday`: back to today, month cleared, applied at once.
  void _backToToday() {
    final today = todayRange(widget.clock());
    setState(() {
      _draft = today;
      _range = today;
      _month = null;
      _load();
    });
  }

  bool get _isToday {
    final today = todayRange(widget.clock());
    return _range.start == today.start && _range.end == today.end;
  }

  Future<void> _pickDate({required bool from}) async {
    final picked = await showDatePicker(
      context: context,
      helpText: from ? 'From' : 'To',
      initialDate: from ? _draft.start : _draft.end,
      // Web: From is capped at To, and To cannot be before From.
      firstDate: from ? DateTime(1900) : _draft.start,
      lastDate: from ? _draft.end : DateTime(2100, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      _draft = from
          ? (start: dateOnly(picked), end: _draft.end)
          : (start: _draft.start, end: dateOnly(picked));
      _month = null;
    });
  }

  Future<void> _refresh() async {
    setState(_load);
    try {
      await _records;
    } catch (_) {
      // Shown by the FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canSeeAttendance(widget.employee)) {
      // Web wording when the page is not granted.
      return CenteredScroll(
        child: MessageView(
          icon: Icons.lock_outline,
          title: 'Access Denied',
          message:
              'You do not have permission to access Attendance User State. '
              'Contact your administrator to request access.',
          action: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: widget.onReturnHome,
            child: const Text('Return to Home'),
          ),
        ),
      );
    }

    final isMock = AppScope.of(context).repository.isMock;
    final page = Responsive.pagePadding(context);

    return FutureBuilder<List<AttendancePunch>>(
      future: _records,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState != ConnectionState.done;
        final records = (loading || snapshot.hasError)
            ? const <AttendancePunch>[]
            : sortPunches(snapshot.data!, _sort);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: page.copyWith(top: AppSpacing.md),
                sliver: SliverList.list(
                  children: [
                    if (isMock) ...[
                      const MockNotice(
                        message: 'Sample attendance records. Not connected to the HRIS.',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _YourRecords(employee: widget.employee),
                    const SizedBox(height: AppSpacing.sm),
                    _FilterPanel(
                      open: _filterOpen,
                      onToggle: () =>
                          setState(() => _filterOpen = !_filterOpen),
                      appliedRange: _range,
                      draft: _draft,
                      draftChanged: _draftChanged,
                      year: _year,
                      years: yearOptions(widget.clock()),
                      // Web: changing the year only clears the month highlight.
                      onYear: (y) => setState(() {
                        _year = y;
                        _month = null;
                      }),
                      onQuick: (q) => setState(() {
                        _draft = q.range(widget.clock());
                        _month = null;
                      }),
                      month: _month,
                      onMonth: (m) => setState(() {
                        _draft = monthRange(_year, m);
                        _month = m;
                      }),
                      onClear: _backToToday,
                      onPickFrom: () => _pickDate(from: true),
                      onPickTo: () => _pickDate(from: false),
                      onSearch: _search,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // Results area: Record Summary + toolbar (scroll target).
                    KeyedSubtree(
                      key: _resultsKey,
                      child: _ResultsHeader(
                        loading: loading,
                        count: records.length,
                        range: _range,
                        onBackToToday: _isToday ? null : _backToToday,
                        toolbar: _RecordsToolbar(
                          count: records.length,
                          sort: _sort,
                          onToggleSort: () => setState(() {
                            _sort = _sort == SortOrder.newestFirst
                                ? SortOrder.oldestFirst
                                : SortOrder.newestFirst;
                            _expanded = null;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: LoadingView(message: 'Loading your records…'),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageView(
                    icon: Icons.error_outline,
                    title: 'Failed to fetch attendance records',
                    color: AppColors.errorFg,
                    action: OutlinedButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Data'),
                    ),
                  ),
                )
              else if (records.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: MessageView(
                    icon: Icons.info_outline,
                    title: 'No records found',
                    message: 'Try adjusting your date range.',
                  ),
                )
              else
                SliverPadding(
                  padding: page.copyWith(bottom: AppSpacing.xl),
                  sliver: SliverList.separated(
                    itemCount: records.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) => _RecordCard(
                      punch: records[i],
                      expanded: _expanded == i,
                      onTap: () =>
                          setState(() => _expanded = _expanded == i ? null : i),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Web "Your Records" box, as one compact row: always the signed-in
/// employee's own records.
class _YourRecords extends StatelessWidget {
  const _YourRecords({required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accentFaint,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Text(
            'YOUR RECORDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.accent.withValues(alpha: 0.65),
            ),
          );
          final name = Text(
            employee.fullName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          );
          final number = Text(
            '#${employee.employeeNumber}',
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          );
          // One row on wide phones; label above name and number when narrow,
          // so the name is not squeezed to a few letters.
          final oneLine =
              constraints.maxWidth >= 400 * Responsive.textScale(context);
          return Row(
            children: [
              const CircleAvatar(
                radius: 14,
                backgroundColor: AppColors.accent,
                child: Icon(Icons.person, color: Colors.white, size: 16),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (oneLine) ...[
                label,
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: name),
                number,
              ] else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Number beside the label; the name gets the full width.
                      Row(
                        children: [
                          Expanded(child: label),
                          number,
                        ],
                      ),
                      name,
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact "Attendance Filter": collapsed it is one row showing the applied
/// period; expanded it holds the web controls and the Search button.
class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.open,
    required this.onToggle,
    required this.appliedRange,
    required this.draft,
    required this.draftChanged,
    required this.year,
    required this.years,
    required this.onYear,
    required this.onQuick,
    required this.month,
    required this.onMonth,
    required this.onClear,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onSearch,
  });

  final bool open;
  final VoidCallback onToggle;
  final DateRange appliedRange;
  final DateRange draft;
  final bool draftChanged;
  final int year;
  final List<int> years;
  final ValueChanged<int> onYear;
  final ValueChanged<QuickPeriod> onQuick;
  final int? month;
  final ValueChanged<int> onMonth;
  final VoidCallback onClear;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final scale = Responsive.textScale(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.filter_list,
                      size: 20,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 10),
                    // Title with the applied period under it, so the period
                    // is never cut off on narrow phones.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Attendance Filter',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.accent,
                            ),
                          ),
                          Text(
                            _rangeText(appliedRange),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      open ? Icons.expand_less : Icons.expand_more,
                      color: AppColors.accent,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  // Side-by-side fields need room for "Quick Dates" and a date.
                  final pairFits = width >= 280 * scale;
                  // Six months per row when each cell stays at least 44 dp
                  // wide; four per row on narrow phones.
                  const gap = 6.0;
                  final columns = (width - 5 * gap) / 6 >= 44 * scale ? 6 : 4;
                  final cellHeight = math.max(40.0, 30 + 10 * scale);

                  final yearField = DropdownButtonFormField<int>(
                    key: const ValueKey('year'),
                    initialValue: year,
                    isDense: true,
                    isExpanded: true,
                    decoration: _compact('Year'),
                    items: [
                      for (final y in years)
                        DropdownMenuItem(value: y, child: Text('$y')),
                    ],
                    onChanged: (y) {
                      if (y != null) onYear(y);
                    },
                  );
                  // Web: always reads "Quick Dates"; picking sets a range.
                  final quickField = DropdownButtonFormField<QuickPeriod>(
                    key: const ValueKey('quick'),
                    isDense: true,
                    isExpanded: true,
                    hint: const Text(
                      'Quick Dates',
                      overflow: TextOverflow.ellipsis,
                    ),
                    decoration: _compact('Quick'),
                    items: [
                      for (final q in QuickPeriod.values)
                        DropdownMenuItem(value: q, child: Text(q.label)),
                    ],
                    selectedItemBuilder: (_) => [
                      for (final _ in QuickPeriod.values)
                        const Text(
                          'Quick Dates',
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                    onChanged: (q) {
                      if (q != null) onQuick(q);
                    },
                  );
                  final fromField = _DateField(
                    label: 'From',
                    value: formatIsoDate(draft.start),
                    onTap: onPickFrom,
                  );
                  final toField = _DateField(
                    label: 'To',
                    value: formatIsoDate(draft.end),
                    onTap: onPickTo,
                  );

                  Widget pair(
                    Widget a,
                    Widget b, {
                    int flexA = 1,
                    int flexB = 1,
                  }) => pairFits
                      ? Row(
                          children: [
                            Expanded(flex: flexA, child: a),
                            const SizedBox(width: 8),
                            Expanded(flex: flexB, child: b),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [a, const SizedBox(height: 8), b],
                        );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pair(yearField, quickField, flexA: 2, flexB: 3),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 32),
                        child: Row(
                          children: [
                            const Expanded(child: _SectionLabel('Month')),
                            if (month != null)
                              TextButton(
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(48, 32),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                onPressed: onClear,
                                child: const Text('Clear'),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          mainAxisExtent: cellHeight,
                        ),
                        itemCount: monthsShort.length,
                        itemBuilder: (context, i) => _MonthCell(
                          label: monthsShort[i],
                          selected: month == i,
                          onTap: () => onMonth(i),
                        ),
                      ),
                      const SizedBox(height: 10),
                      pair(fromField, toField),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('search'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: onSearch,
                        icon: const Icon(Icons.search, size: 20),
                        label: const Text('Search'),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        draftChanged
                            ? 'Selected: ${_rangeText(draft)}. Tap Search to apply.'
                            : 'Changes apply when you tap Search. Clear returns to today right away.',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Web "Record Summary" (count and period) above the records, with "Back to
/// today" and the records toolbar.
class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.loading,
    required this.count,
    required this.range,
    required this.onBackToToday,
    required this.toolbar,
  });

  final bool loading;
  final int count;
  final DateRange range;
  final VoidCallback? onBackToToday;
  final Widget toolbar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.accentFaint,
            borderRadius: BorderRadius.circular(AppSpacing.sm),
            border: Border.all(color: AppColors.accentBorder),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final summary = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('Record Summary'),
                  const SizedBox(height: 2),
                  Text(
                    loading
                        ? 'Loading records...'
                        : '$count ${count == 1 ? 'record' : 'records'} found',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    _rangeText(range),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              );
              if (onBackToToday == null) return summary;
              final back = TextButton(
                onPressed: onBackToToday,
                child: const Text('Back to today'),
              );
              // "Back to today" sits beside the summary when there is room,
              // otherwise under it.
              return constraints.maxWidth >= 300 * Responsive.textScale(context)
                  ? Row(
                      children: [
                        Expanded(child: summary),
                        back,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [summary, back],
                    );
            },
          ),
        ),
        const SizedBox(height: 4),
        toolbar,
      ],
    );
  }
}

String _rangeText(DateRange r) =>
    '${formatIsoDate(r.start)} → ${formatIsoDate(r.end)}';

InputDecoration _compact(String label) => InputDecoration(
  isDense: true,
  labelText: label,
  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
);

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: AppColors.accent.withValues(alpha: 0.7),
      ),
    );
  }
}

/// Web month cell: outlined by default, filled when selected.
class _MonthCell extends StatelessWidget {
  const _MonthCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: selected ? AppColors.accentDark : AppColors.accentBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InputDecorator(
        decoration: _compact(label).copyWith(
          suffixIcon: const Icon(Icons.calendar_today, size: 15),
          suffixIconConstraints: const BoxConstraints(
            minWidth: 32,
            minHeight: 20,
          ),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

/// Web records toolbar: "Attendance States", punch count and sort (the count
/// and sort only appear when there are records).
class _RecordsToolbar extends StatelessWidget {
  const _RecordsToolbar({
    required this.count,
    required this.sort,
    required this.onToggleSort,
  });

  final int count;
  final SortOrder sort;
  final VoidCallback onToggleSort;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.assignment_outlined,
              size: 16,
              color: AppColors.accent,
            ),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Attendance States',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text,
                ),
              ),
            ),
            if (count > 0)
              Text(
                '$count punch${count == 1 ? '' : 'es'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        if (count > 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onToggleSort,
              icon: Icon(
                sort == SortOrder.oldestFirst
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 16,
              ),
              label: Text('Sort ${sort.label}'),
            ),
          ),
      ],
    );
  }
}

/// One punch: DATE, TIME, STATUS and BRANCH, with DETAILS on tap.
class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.punch,
    required this.expanded,
    required this.onTap,
  });

  final AttendancePunch punch;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          formatRecordDate(punch.at),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          formatPunchTime(punch.at),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PunchStatusChip(state: punch.state),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  BranchChip(branch: punch.branch),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      punch.deviceName ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  Text(
                    expanded ? 'Hide' : 'View',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: AppColors.accent,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.accentFaint,
                    borderRadius: BorderRadius.circular(AppSpacing.sm),
                  ),
                  // Same fields and values as the web row details, in two
                  // or three equal columns depending on the width.
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const spacing = AppSpacing.md;
                      final minCol = 110 * Responsive.textScale(context);
                      final w = constraints.maxWidth;
                      final cols = w >= 3 * minCol + 2 * spacing
                          ? 3
                          : w >= 2 * minCol + spacing
                          ? 2
                          : 1;
                      final colWidth = (w - (cols - 1) * spacing) / cols;
                      return Wrap(
                        spacing: spacing,
                        runSpacing: AppSpacing.md,
                        children: [
                          for (final (label, value) in [
                            ('Employee ID', punch.employeeNumber),
                            ('Date', formatPunchDate(punch.at)),
                            ('Time', formatPunchTime(punch.at)),
                            ('Status', punchStatusLabel(punch.state)),
                            ('Branch', branchLabel(punch.branch)),
                            ('Device', orEmpty(punch.deviceName)),
                          ])
                            SizedBox(
                              width: colWidth,
                              child: _Detail(label, value),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.faint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}
