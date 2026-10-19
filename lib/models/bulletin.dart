/// Kinds of item in the web Home carousel and "Up Next" list.
enum BulletinKind {
  holiday('Holiday'),
  suspension('Suspension'),
  announcement('Announcement');

  const BulletinKind(this.label);

  /// Badge text used by Home.jsx / HomeAdmin.jsx.
  final String label;
}

/// A Home event from the approved protected holiday and suspension APIs.
///
/// Announcement integration remains intentionally disconnected.
class Bulletin {
  const Bulletin({
    required this.id,
    required this.kind,
    required this.title,
    required this.start,
    this.end,
    this.about,
    this.imageUrl,
    this.active = true,
  });

  final String id;
  final BulletinKind kind;
  final String title;
  final String? about;

  /// Validated same-backend `/uploads/` image, when supplied by an approved
  /// protected response.
  final Uri? imageUrl;

  /// `date_start` (or `date`).
  final DateTime start;

  /// `date_end`, when set.
  final DateTime? end;

  /// Holidays only: `status === "active"`.
  final bool active;
}
