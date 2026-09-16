/// One showing, soon, with the film and branch it belongs to already
/// resolved — built for the Home screen's "Starting Soon" row, which
/// needs the poster/title/chain/branch/time together rather than the
/// bare ids [Showtime] carries. Comes from a `showtimes` row embedding
/// `films` and `branches` (both real foreign keys — see
/// Database.getStartingSoon), not from a separate table of its own.
class UpcomingShowtime {
  const UpcomingShowtime({
    required this.filmId,
    required this.filmTitle,
    required this.posterUrl,
    required this.cinemaName,
    required this.branchId,
    required this.branchName,
    required this.screenType,
    required this.time,
  });

  factory UpcomingShowtime.fromJson(Map<String, dynamic> json) {
    final film = json["films"] as Map<String, dynamic>?;
    final branch = json["branches"] as Map<String, dynamic>?;

    return UpcomingShowtime(
      filmId: json["film_id"],
      filmTitle: film?["title"] ?? "Untitled",
      posterUrl: film?["poster_url"],
      cinemaName: branch?["cinema_name"] ?? "",
      branchId: branch?["branch_id"] as int?,
      branchName: branch?["branch_name"] ?? "",
      screenType: json["screen_type"] ?? "",
      time: DateTime.parse(json["show_time"]).toLocal(),
    );
  }

  /// Points at [Film.filmId] — what a tap on this row uses to load the
  /// full film before opening the Schedule Card with it preselected.
  final int filmId;

  final String filmTitle;
  final String? posterUrl;
  final String cinemaName;

  /// Points at [Branch.id] — what a tap on this row uses to preselect
  /// the exact branch this showing is at, not just its chain. Null only
  /// if the `branches` join came back empty, in which case the Schedule
  /// Card falls back to an unset branch dropdown.
  final int? branchId;

  final String branchName;
  final String screenType;
  final DateTime time;
}
