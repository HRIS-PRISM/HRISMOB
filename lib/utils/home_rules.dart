import '../models/bulletin.dart';
import 'attendance_rules.dart' show dateOnly;

/// Home dashboard rules ported from the web HRIS (Home.jsx, HomeAdmin.jsx,
/// utils/carouselVisibility.js).

/// Web `CAROUSEL_GRACE_DAYS`.
const carouselGraceDays = 7;

/// Web `isStillShowing`: visible through `end + 7 days`; no end date means
/// always visible.
bool isStillShowing(DateTime? end, DateTime now) {
  if (end == null) return true;
  final last = dateOnly(end).add(const Duration(days: carouselGraceDays));
  return !dateOnly(now).isAfter(last);
}

/// Web `carouselItems`: active, unexpired holidays + unexpired suspensions +
/// unexpired announcements, newest start date first.
List<Bulletin> carouselItems(Iterable<Bulletin> all, DateTime now) {
  final items =
      all
          .where(
            (b) => switch (b.kind) {
              // Holidays use `date_end || date`.
              BulletinKind.holiday =>
                b.active && isStillShowing(b.end ?? b.start, now),
              BulletinKind.suspension => isStillShowing(b.end, now),
              BulletinKind.announcement => isStillShowing(b.end, now),
            },
          )
          .toList()
        ..sort((a, b) => b.start.compareTo(a.start));
  return items;
}

class UpNextItem {
  const UpNextItem({
    required this.bulletin,
    required this.date,
    required this.when,
  });

  final Bulletin bulletin;
  final DateTime date;

  /// "Today", "Tomorrow" or "in Nd".
  final String when;
}

/// Web `upNextItems` (Job Order Home): upcoming holidays, suspensions and
/// announcements, soonest first, at most 8. A holiday or suspension already
/// in progress is dated today. (The web list also includes the user's own
/// notes and events, which are not part of the mobile app.)
List<UpNextItem> upNextItems(Iterable<Bulletin> all, DateTime now) {
  final today = dateOnly(now);
  DateTime later(DateTime a, DateTime b) => a.isAfter(b) ? a : b;

  final items = <(Bulletin, DateTime)>[];
  for (final b in all) {
    switch (b.kind) {
      case BulletinKind.holiday:
        if (b.active && !dateOnly(b.end ?? b.start).isBefore(today)) {
          items.add((b, later(dateOnly(b.start), today)));
        }
      case BulletinKind.suspension:
        if (!dateOnly(b.end ?? b.start).isBefore(today)) {
          items.add((b, later(dateOnly(b.start), today)));
        }
      case BulletinKind.announcement:
        if (!dateOnly(b.start).isBefore(today)) {
          items.add((b, dateOnly(b.start)));
        }
    }
  }
  items.sort((a, b) {
    final byDate = a.$2.compareTo(b.$2);
    return byDate != 0 ? byDate : a.$1.title.compareTo(b.$1.title);
  });

  return [
    for (final (b, date) in items.take(8))
      UpNextItem(
        bulletin: b,
        date: date,
        when: switch (date.difference(today).inDays) {
          <= 0 => 'Today',
          1 => 'Tomorrow',
          final d => 'in ${d}d',
        },
      ),
  ];
}
