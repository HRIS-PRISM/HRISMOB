import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app_scope.dart';
import '../models/attendance.dart';
import '../models/bulletin.dart';
import '../models/employee.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../utils/attendance_rules.dart';
import '../utils/formatters.dart';
import '../utils/home_rules.dart';
import '../utils/safe_bulletin_description.dart';
import 'attendance_widgets.dart';
import 'common.dart';

final _longDate = DateFormat('EEEE, MMMM d, y', 'en_US');
final _monthLabel = DateFormat('MMMM y', 'en_US');
final _shortDay = DateFormat('EEE, MMM d', 'en_US');
final _hm = DateFormat('h:mm a', 'en_US');

/// Shared card shell: icon + title header row, like the web Home cards.
class HomeCard extends StatelessWidget {
  const HomeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.titleExtra,
  });

  final IconData icon;
  final String title;
  final Widget? titleExtra;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Responsive.cardPadding(context);
    return Card(
      child: Padding(
        padding: EdgeInsets.fromLTRB(p, 12, p, p),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.accentFaint,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.accent),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                      ),
                      ?titleExtra,
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _MonthNav extends StatelessWidget {
  const _MonthNav({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    // 36 dp buttons: comfortably tappable without crowding the card header.
    Widget btn(IconData icon, String tip, VoidCallback onTap) => IconButton(
      tooltip: tip,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      padding: EdgeInsets.zero,
      iconSize: 14,
      style: IconButton.styleFrom(
        side: const BorderSide(color: AppColors.accentBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      color: AppColors.accent,
      onPressed: onTap,
      icon: Icon(icon),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.arrow_back_ios_new, 'Previous month', onPrev),
        Flexible(
          child: ConstrainedBox(
            // Wide enough for the longest month name, so the arrows stay put.
            constraints: const BoxConstraints(minWidth: 112),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ),
        ),
        btn(Icons.arrow_forward_ios, 'Next month', onNext),
      ],
    );
  }
}

// ── Announcements carousel (Home.jsx / HomeAdmin.jsx) ──────────────────────

/// Announcements, active holidays and suspensions, newest first. Swipe or
/// wait for the next slide; tap a slide for its details.
class BulletinCarousel extends StatefulWidget {
  const BulletinCarousel({
    super.key,
    required this.emptyText,
    this.clock = DateTime.now,
    this.liveEvents = false,
    this.onRetry,
    this.imageProviderBuilder,
  });

  /// The two web dashboards word the empty state differently.
  final String emptyText;
  final DateTime Function() clock;
  final bool liveEvents;
  final VoidCallback? onRetry;

  /// Injectable only so image success/failure can be tested without a live
  /// server. Production uses a [NetworkImage] for the validated URL.
  final ImageProvider<Object> Function(Uri url)? imageProviderBuilder;

  @override
  State<BulletinCarousel> createState() => _BulletinCarouselState();
}

class _BulletinCarouselState extends State<BulletinCarousel> {
  Future<List<Bulletin>>? _items;
  final _pages = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= AppScope.of(context).repository
        .fetchBulletins()
        .then((all) => carouselItems(all, widget.clock()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _startTimer(int count) {
    if (_timer != null || count < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!_pages.hasClients) return;
      _pages.animateToPage(
        (_index + 1) % count,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  void _showDetails(Bulletin b) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        key: const ValueKey('bulletin-detail-sheet-content'),
        width: double.infinity,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KindBadge(kind: b.kind, onDark: false),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    b.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _longDate.format(b.start),
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (b.imageUrl != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _BulletinDetailImage(
                      bulletin: b,
                      imageProviderBuilder: widget.imageProviderBuilder,
                    ),
                  ],
                  if ((b.about ?? '').isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _BulletinDescriptionText(value: b.about!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Banner height: about 0.42 of the width (a wide banner), kept between 160
  /// and 220 dp and to about 40% of a short (landscape) screen, plus room
  /// for a larger system font.
  static double heightFor(
    double width,
    double screenHeight,
    double textScale,
  ) =>
      math.min(
        (width * 0.42).clamp(160.0, 220.0),
        math.max(150.0, screenHeight * 0.4),
      ) +
      (textScale - 1) * 80;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: heightFor(
          constraints.maxWidth,
          MediaQuery.sizeOf(context).height,
          Responsive.textScale(context),
        ),
        child: _card(context),
      ),
    );
  }

  Widget _card(BuildContext context) {
    return SizedBox(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: FutureBuilder<List<Bulletin>>(
          future: _items,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return LoadingView(
                message: widget.liveEvents
                    ? 'Loading holidays and suspensions...'
                    : 'Loading announcements...',
              );
            }
            if (snap.hasError) {
              return _HomeEventsError(
                message: 'Could not load holidays and suspensions.',
                onRetry: widget.onRetry,
              );
            }
            final items = snap.data ?? const <Bulletin>[];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.flag,
                        size: 48,
                        color: AppColors.accentBorder,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.emptyText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              );
            }
            _startTimer(items.length);
            return Stack(
              children: [
                PageView.builder(
                  controller: _pages,
                  itemCount: items.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _Slide(
                    bulletin: items[i],
                    onTap: () => _showDetails(items[i]),
                    imageProviderBuilder: widget.imageProviderBuilder,
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Row(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(left: 5),
                          width: i == _index ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BulletinDescriptionText extends StatelessWidget {
  const _BulletinDescriptionText({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    final runs = parseBulletinDescription(value);
    return Text.rich(
      TextSpan(
        children: [
          for (final run in runs)
            TextSpan(
              text: run.text,
              style: TextStyle(
                fontWeight: run.bold ? FontWeight.bold : null,
                fontStyle: run.italic ? FontStyle.italic : null,
                decoration: run.underline ? TextDecoration.underline : null,
              ),
            ),
        ],
      ),
      key: const ValueKey('bulletin-description'),
    );
  }
}

class _BulletinDetailImage extends StatelessWidget {
  const _BulletinDetailImage({
    required this.bulletin,
    this.imageProviderBuilder,
  });

  final Bulletin bulletin;
  final ImageProvider<Object> Function(Uri url)? imageProviderBuilder;

  @override
  Widget build(BuildContext context) {
    final imageUrl = bulletin.imageUrl!;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              key: ValueKey('bulletin-detail-image-fallback'),
              decoration: BoxDecoration(gradient: _Slide._gradient),
            ),
            Image(
              key: ValueKey('bulletin-detail-image'),
              image:
                  imageProviderBuilder?.call(imageUrl) ??
                  NetworkImage(imageUrl.toString()),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded || frame != null
                  ? child
                  : const SizedBox.shrink(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.bulletin,
    required this.onTap,
    this.imageProviderBuilder,
  });

  final Bulletin bulletin;
  final VoidCallback onTap;
  final ImageProvider<Object> Function(Uri url)? imageProviderBuilder;

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xF0370808), Color(0xD15A1414), AppColors.accentDark],
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            key: ValueKey('bulletin-gradient-fallback'),
            decoration: BoxDecoration(gradient: _gradient),
          ),
          if (bulletin.imageUrl case final imageUrl?)
            Image(
              key: ValueKey('bulletin-image-${bulletin.id}'),
              image:
                  imageProviderBuilder?.call(imageUrl) ??
                  NetworkImage(imageUrl.toString()),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
                  wasSynchronouslyLoaded || frame != null
                  ? child
                  : const SizedBox.shrink(),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          const DecoratedBox(
            key: ValueKey('bulletin-gradient-overlay'),
            decoration: BoxDecoration(gradient: _gradient),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _KindBadge(kind: bulletin.kind, onDark: true),
                const SizedBox(height: 6),
                Text(
                  bulletin.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 13,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        _longDate.format(bulletin.start),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind, required this.onDark});

  final BulletinKind kind;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: onDark ? const Color(0xD9500F0F) : AppColors.accentFaint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: onDark ? Colors.white24 : AppColors.accentBorder,
        ),
      ),
      child: Text(
        kind.label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
          color: onDark ? Colors.white : AppColors.accent,
        ),
      ),
    );
  }
}

// ── "My Attendance" (AttendanceCalendar.jsx) ──────────────────────────────

const _chipColors = {
  AttendanceCode.present: (Color(0xFFDCFCE7), Color(0xFF166534)),
  AttendanceCode.absent: (Color(0xFFFEE2E2), Color(0xFF991B1B)),
  AttendanceCode.vacationLeave: (Color(0xFFDBEAFE), Color(0xFF1E3A8A)),
  AttendanceCode.sickLeave: (Color(0xFFFEF9C3), Color(0xFF854D0E)),
  AttendanceCode.nonWorkingDay: (Color(0xFFF1F5F9), Color(0xFF64748B)),
  AttendanceCode.holiday: (Color(0xFFFDE8D8), Color(0xFF9A3412)),
  AttendanceCode.late: (Color(0xFFFEF3C7), Color(0xFF92400E)),
};

class _CodeChip extends StatelessWidget {
  const _CodeChip(this.code);

  final AttendanceCode code;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _chipColors[code]!;
    return Tooltip(
      message: code.label,
      child: Container(
        width: 30,
        height: 22,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(5),
        ),
        // A fixed badge: three-letter codes (NWD) stay inside it at any
        // system font size.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            code.code,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

/// The employee's attendance codes for a month. [calendar] selects the
/// month-grid form the web uses for Job Orders; otherwise the day strip.
/// [hideLeave] drops Vacation/Sick leave (Job Orders have no leave).
class MyAttendanceCard extends StatefulWidget {
  const MyAttendanceCard({
    super.key,
    required this.employee,
    this.calendar = false,
    this.hideLeave = false,
    this.clock = DateTime.now,
  });

  final Employee employee;
  final bool calendar;
  final bool hideLeave;
  final DateTime Function() clock;

  @override
  State<MyAttendanceCard> createState() => _MyAttendanceCardState();
}

class _MyAttendanceCardState extends State<MyAttendanceCard> {
  late DateTime _cursor;
  Future<AttendanceMonth>? _month;
  final _strip = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = widget.clock();
    _cursor = DateTime(now.year, now.month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _month ??= _load();
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  Future<AttendanceMonth> _load() => AppScope.of(context).repository
      .fetchAttendanceMonth(
        widget.employee.employeeNumber,
        year: _cursor.year,
        month: _cursor.month,
      );

  void _move(int delta) => setState(() {
    _cursor = DateTime(_cursor.year, _cursor.month + delta);
    _month = _load();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AttendanceMonth>(
      future: _month,
      builder: (context, snap) {
        final m = snap.data;
        final ready = snap.connectionState == ConnectionState.done && m != null;
        final ot = m?.officialTime;
        final otLabel = (ot != null && ot.isAssigned)
            ? '${formatOfficialTime(ot.timeIn)} – ${formatOfficialTime(ot.timeOut)}'
            : 'No official time';
        return HomeCard(
          icon: Icons.calendar_month,
          title: 'My Attendance',
          titleExtra: const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              message:
                  'Same as your DTR. A blank day means no biometric punch was '
                  'recorded — it is not counted as absent.',
              child: Icon(Icons.info_outline, size: 15, color: AppColors.faint),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 6,
                children: [
                  _MonthNav(
                    label: ready ? _monthLabel.format(_cursor) : '…',
                    onPrev: () => _move(-1),
                    onNext: () => _move(1),
                  ),
                  if (ready)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ot?.isAssigned == true
                            ? AppColors.accentFaint
                            : const Color(0x0A000000),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: AppColors.accentBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.access_time,
                            size: 12,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              otLabel,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (!ready)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else ...[
                _Legend(
                  month: m,
                  calendar: widget.calendar,
                  hideLeave: widget.hideLeave,
                ),
                const SizedBox(height: AppSpacing.md),
                widget.calendar
                    ? _MonthGrid(
                        month: m,
                        hideLeave: widget.hideLeave,
                        today: widget.clock(),
                      )
                    : _DayStrip(
                        month: m,
                        today: widget.clock(),
                        controller: _strip,
                      ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({
    required this.month,
    required this.calendar,
    required this.hideLeave,
  });

  final AttendanceMonth month;
  final bool calendar;
  final bool hideLeave;

  @override
  Widget build(BuildContext context) {
    // Web: the strip shows every code (minus leave for Job Orders); the
    // calendar shows only P, L, A (+ VL, SL) plus Holiday/Suspension tints.
    final codes = AttendanceCode.values.where((c) {
      if (hideLeave && c.isLeave) return false;
      if (calendar) {
        return c == AttendanceCode.present ||
            c == AttendanceCode.late ||
            c == AttendanceCode.absent ||
            c.isLeave;
      }
      return true;
    });
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final c in codes) _LegendItem(code: c, count: month.count(c)),
        if (calendar) ...[
          const _TintLegend(label: 'Holiday'),
          const _TintLegend(label: 'Suspension'),
        ],
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.code, required this.count});

  final AttendanceCode code;
  final int count;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _chipColors[code]!;
    final on = count > 0;
    return Opacity(
      opacity: on ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(3, 3, 8, 3),
        decoration: BoxDecoration(
          color: on ? bg : const Color(0x08000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 22, minHeight: 18),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                code.code,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                code.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: on ? fg : AppColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: on ? fg : AppColors.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TintLegend extends StatelessWidget {
  const _TintLegend({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = label == 'Holiday' ? eventHoliday : eventSuspension;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    );
  }
}

/// Web day strip: Su/M/T/W/Th/F/Sa, day number, code chip (or a dot when
/// blank). Scrolls so today is in view.
class _DayStrip extends StatefulWidget {
  const _DayStrip({
    required this.month,
    required this.today,
    required this.controller,
  });

  final AttendanceMonth month;
  final DateTime today;
  final ScrollController controller;

  @override
  State<_DayStrip> createState() => _DayStripState();
}

class _DayStripState extends State<_DayStrip> {
  // Tile size grows with the system font so labels never clip.
  double get _tileWidth =>
      46 * math.max(1.0, Responsive.textScale(context) * 0.9);
  static const _names = ['M', 'T', 'W', 'Th', 'F', 'Sa', 'Su'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday());
  }

  @override
  void didUpdateWidget(_DayStrip old) {
    super.didUpdateWidget(old);
    if (old.month.month != widget.month.month ||
        old.month.year != widget.month.year) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday());
    }
  }

  void _centerToday() {
    final c = widget.controller;
    if (!c.hasClients) return;
    final m = widget.month;
    final isThisMonth =
        widget.today.year == m.year && widget.today.month == m.month;
    final target = isThisMonth
        ? (widget.today.day - 1) * (_tileWidth + 4) -
              c.position.viewportDimension / 2 +
              _tileWidth / 2
        : 0.0;
    c.jumpTo(target.clamp(0.0, c.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.month;
    final days = DateTime(m.year, m.month + 1, 0).day;
    return SizedBox(
      height: 58 + 26 * Responsive.textScale(context),
      child: ListView.separated(
        controller: widget.controller,
        scrollDirection: Axis.horizontal,
        itemCount: days,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final date = DateTime(m.year, m.month, i + 1);
          final isToday = dateOnly(widget.today) == date;
          final weekend = date.weekday >= DateTime.saturday;
          final code = m.codes[i + 1];
          return Container(
            width: _tileWidth,
            decoration: BoxDecoration(
              color: isToday
                  ? AppColors.accentFaint
                  : weekend
                  ? const Color(0x06000000)
                  : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isToday ? AppColors.accent : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _names[date.weekday - 1],
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: weekend ? AppColors.faint : AppColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${i + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isToday
                        ? AppColors.accent
                        : weekend
                        ? AppColors.faint
                        : AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                code != null
                    ? _CodeChip(code)
                    : const SizedBox(
                        width: 30,
                        height: 22,
                        child: Center(
                          child: CircleAvatar(
                            radius: 2,
                            backgroundColor: Color(0x1F000000),
                          ),
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Web calendar form (Mon–Sun grid): P/L/A (+VL/SL) badges; holidays and
/// suspensions shown as a tinted day with their name.
///
/// On phones the cells are too narrow for a readable name, so the tinted
/// days are listed by name under the grid instead.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.hideLeave,
    required this.today,
  });

  final AttendanceMonth month;
  final bool hideLeave;
  final DateTime today;

  static const _gap = 4.0;

  @override
  Widget build(BuildContext context) {
    final m = month;
    final days = DateTime(m.year, m.month + 1, 0).day;
    final lead = DateTime(m.year, m.month, 1).weekday - 1; // Monday first
    const headers = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    final scale = Responsive.textScale(context);
    bool badge(AttendanceCode? c) =>
        c == AttendanceCode.present ||
        c == AttendanceCode.late ||
        c == AttendanceCode.absent ||
        (!hideLeave && (c?.isLeave ?? false));
    Color tintFor(int d) =>
        m.suspensionDays.contains(d) ? eventSuspension : eventHoliday;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cell = (constraints.maxWidth - 6 * _gap) / 7;
        final namesInCells = cell >= 64;
        // Day number + badge, or day number + two lines of name.
        final extent = namesInCells
            ? math.max(cell * 0.85, 60 * scale)
            : math.max(cell * 0.95, 26 + 18 * scale);
        final named = m.holidayNames.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        headers[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: i >= 5 ? AppColors.faint : AppColors.accent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: _gap,
                crossAxisSpacing: _gap,
                mainAxisExtent: extent,
              ),
              itemCount: lead + days,
              itemBuilder: (context, index) {
                if (index < lead) return const SizedBox();
                final d = index - lead + 1;
                final date = DateTime(m.year, m.month, d);
                final code = m.codes[d];
                final name = m.holidayNames[d];
                final isToday = dateOnly(today) == date;
                final weekend = date.weekday >= DateTime.saturday;
                final tint = tintFor(d);
                return Container(
                  decoration: BoxDecoration(
                    color: name != null
                        ? tint.withValues(alpha: 0.12)
                        : isToday
                        ? AppColors.accentFaint
                        : weekend
                        ? const Color(0x05000000)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isToday
                          ? AppColors.accent
                          : name != null
                          ? tint.withValues(alpha: 0.4)
                          : const Color(0x12000000),
                    ),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$d',
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          fontWeight: isToday
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isToday
                              ? AppColors.accent
                              : weekend
                              ? AppColors.faint
                              : AppColors.text,
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: badge(code)
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _CodeChip(code!),
                                )
                              : name != null && namesInCells
                              ? Text(
                                  name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: tint,
                                    height: 1.1,
                                  ),
                                )
                              : const SizedBox(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (!namesInCells && named.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              for (final MapEntry(key: d, value: name) in named)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: tintFor(d).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(
                            color: tintFor(d).withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${_shortDay.format(DateTime(m.year, m.month, d))} · $name',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tintFor(d),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

// ── "Time Logs" (TimeLogsCard.jsx, Job Order Home) ─────────────────────────

class TimeLogsCard extends StatefulWidget {
  const TimeLogsCard({
    super.key,
    required this.employee,
    required this.onViewAll,
    this.clock = DateTime.now,
  });

  final Employee employee;

  /// Opens the full Attendance page; null when the page is not granted.
  final VoidCallback? onViewAll;
  final DateTime Function() clock;

  @override
  State<TimeLogsCard> createState() => _TimeLogsCardState();
}

class _TimeLogsCardState extends State<TimeLogsCard> {
  late DateTime _cursor;
  Future<List<AttendancePunch>>? _punches;

  @override
  void initState() {
    super.initState();
    final now = widget.clock();
    _cursor = DateTime(now.year, now.month);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _punches ??= _load();
  }

  Future<List<AttendancePunch>> _load() =>
      AppScope.of(context).repository.fetchPunches(
        widget.employee.employeeNumber,
        start: DateTime(_cursor.year, _cursor.month, 1),
        end: DateTime(_cursor.year, _cursor.month + 1, 0),
      );

  void _move(int delta) => setState(() {
    _cursor = DateTime(_cursor.year, _cursor.month + delta);
    _punches = _load();
  });

  @override
  Widget build(BuildContext context) {
    final monthLabel = _monthLabel.format(_cursor);
    return HomeCard(
      icon: Icons.fingerprint,
      title: 'Time Logs',
      trailing: widget.onViewAll == null
          ? null
          : TextButton(
              onPressed: widget.onViewAll,
              child: const Text('View all'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _MonthNav(
              label: monthLabel,
              onPrev: () => _move(-1),
              onNext: () => _move(1),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<List<AttendancePunch>>(
            future: _punches,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.accent,
                        ),
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Loading time logs…',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final punches = snap.data ?? const <AttendancePunch>[];
              if (punches.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.fingerprint,
                        size: 44,
                        color: Color(0x24000000),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'No punches in $monthLabel.',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }
              // Newest day first; punches within a day newest first.
              final byDay = <DateTime, List<AttendancePunch>>{};
              for (final p in sortPunches(punches, SortOrder.newestFirst)) {
                byDay.putIfAbsent(p.day, () => []).add(p);
              }
              final today = dateOnly(widget.clock());
              // Web: the whole month scrolls inside the card body.
              // Box height follows the screen (taller phones show more)
              // but never takes over a short screen.
              final screenH = MediaQuery.sizeOf(context).height;
              final timeWidth = 70 * Responsive.textScale(context);
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (screenH * 0.38).clamp(200.0, 360.0),
                ),
                child: ListView(
                  shrinkWrap: true,
                  primary: false,
                  children: [
                    for (final MapEntry(key: day, value: list)
                        in byDay.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Text(
                          '${day == today ? 'Today · ' : ''}${_shortDay.format(day)}'
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                            color: day == today
                                ? AppColors.accent
                                : AppColors.faint,
                          ),
                        ),
                      ),
                      for (final p in list)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          // Time, status and branch share a line when they
                          // fit and wrap on narrow phones or large text.
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SizedBox(
                                width: timeWidth,
                                child: Text(
                                  _hm.format(p.at),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              PunchStatusChip(state: p.state),
                              BranchChip(branch: p.branch),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── "Up Next" (Home.jsx, Job Order Home) ──────────────────────────────────

class UpNextCard extends StatefulWidget {
  const UpNextCard({
    super.key,
    this.clock = DateTime.now,
    this.liveEvents = false,
    this.onRetry,
  });

  final DateTime Function() clock;
  final bool liveEvents;
  final VoidCallback? onRetry;

  @override
  State<UpNextCard> createState() => _UpNextCardState();
}

class _UpNextCardState extends State<UpNextCard> {
  Future<List<UpNextItem>>? _items;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _items ??= AppScope.of(context).repository
        .fetchBulletins()
        .then((all) => upNextItems(all, widget.clock()));
  }

  @override
  Widget build(BuildContext context) {
    return HomeCard(
      icon: Icons.event,
      title: 'Up Next',
      child: FutureBuilder<List<UpNextItem>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            );
          }
          if (snap.hasError) {
            return _HomeEventsError(
              message: widget.liveEvents
                  ? 'Could not load holidays and suspensions.'
                  : 'Could not load upcoming notices.',
              onRetry: widget.onRetry,
            );
          }
          final items = snap.data ?? const <UpNextItem>[];
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing coming up.',
                style: TextStyle(color: AppColors.muted),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              // Narrow rows: type and "when" on top, the full title below.
              final stacked =
                  constraints.maxWidth < 360 * Responsive.textScale(context);
              return Column(
                children: [
                  for (final (i, it) in items.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: stacked ? _upNextStacked(it) : _upNextRow(it),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HomeEventsError extends StatelessWidget {
  const _HomeEventsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 24, color: AppColors.errorFg),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.errorFg),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _upNextRow(UpNextItem it) => Row(
  children: [
    StatusPill(
      label: it.bulletin.kind.label,
      color: _kindColor(it.bulletin.kind),
    ),
    const SizedBox(width: 8),
    Expanded(
      child: Text(
        it.bulletin.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    const SizedBox(width: 8),
    Text(it.when, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
  ],
);

Widget _upNextStacked(UpNextItem it) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              label: it.bulletin.kind.label,
              color: _kindColor(it.bulletin.kind),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          it.when,
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
      ],
    ),
    const SizedBox(height: 4),
    Text(
      it.bulletin.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  ],
);

Color _kindColor(BulletinKind kind) => switch (kind) {
  BulletinKind.holiday => eventHoliday,
  BulletinKind.suspension => eventSuspension,
  BulletinKind.announcement => eventAnnouncement,
};

// Web constants/eventTypeColors.js
const eventAnnouncement = Color(0xFF6D2323);
const eventSuspension = Color(0xFFC62828);
const eventHoliday = Color(0xFFE65100);
