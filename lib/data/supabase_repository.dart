import '../models/attendance.dart';
import '../models/branch.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/film_break.dart';
import '../models/schedule.dart';
import '../models/showtime.dart';
import '../models/upcoming_showtime.dart';
import '../models/yearly_recap.dart';
import '../services/database.dart';
import '../services/gemini_api.dart';
import 'ticked_repository.dart';

/// The real implementation of the frozen contract — every screen now
/// reads Supabase through this. Nothing in the app is seeded, stubbed
/// or invented any more: films, showtimes and branches come from the
/// scrapers, chains and their researched ad blocks from `cinemas`, and
/// history from the signed-in user's own `movies_seen` rows.
class SupabaseRepository implements TickedRepository {
  final Database _db = Database();
  final GeminiApi _gemini = GeminiApi();

  /// `cinemas` is five hand-maintained rows that never change during a
  /// session, and [adMinutes] is asked for on every edit of the
  /// Schedule Card — worth holding rather than re-fetching.
  List<Cinema>? _cinemaCache;

  // ---- Reference data -----------------------------------------------------

  @override
  Future<List<Cinema>> cinemas() async {
    return _cinemaCache ??= await _db.getAllCinemas();
  }

  @override
  Future<List<Branch>> branches(String cinemaName) => _db.getBranches(cinemaName);

  @override
  Future<int> adMinutes(String cinemaName, int durationMin) async {
    final all = await cinemas();

    for (final cinema in all) {
      if (cinema.name == cinemaName) {
        return cinema.adMinutesFor(durationMin);
      }
    }
    throw Exception("No ad timing on record for $cinemaName.");
  }

  // ---- Films ---------------------------------------------------------------

  @override
  Future<List<Film>> nowShowing() => _db.getNowShowing();

  /// Which chain's site each scraper reads, as the `films.source` token
  /// it stamps its rows with. A chain that isn't in here has no scraper
  /// yet, so it genuinely has no listings and its row on the Cinemas
  /// tab shows an empty state. Adding a scraper means adding a line
  /// here, not changing a screen.
  static const Map<String, String> _sourceByCinema = {
    'VOX': 'vox',
    'Muvi': 'muvi',
    'Reel': 'reel',
    'CINEHOUSE': 'cinehouse',
    'Scene': 'scene',
  };

  @override
  Future<List<Film>> filmsForCinema(String cinemaName) async {
    final source = _sourceByCinema[cinemaName];

    if (source == null) {
      return const [];
    }
    return _db.getFilmsBySource(source);
  }

  /// Null when nothing matches — the caller has to cope rather than be
  /// handed the wrong film. Only VOX is scraped, so a ticket from any
  /// other chain legitimately finds nothing.
  @override
  Future<Film?> matchFilmByTitle(String ocrTitle) async {
    final needle = ocrTitle.trim();
    if (needle.isEmpty) {
      return null;
    }

    final matches = await _db.searchFilmsByTitle(needle);
    if (matches.isEmpty) {
      return null;
    }

    // Prefer an exact title over a substring hit — searching "colony"
    // should not return "The Colony Chronicles" when "Colony" is right
    // there.
    for (final film in matches) {
      if (film.title.toLowerCase() == needle.toLowerCase()) {
        return film;
      }
    }
    return matches.first;
  }

  @override
  Future<Film> filmDetails(int filmId) async {
    final film = await _db.getFilm(filmId);

    if (film == null) {
      throw Exception("That film is no longer listed.");
    }
    return film;
  }

  // ---- Scheduling -----------------------------------------------------------

  @override
  Future<Schedule> buildSchedule({
    required int branchId,
    required int filmId,
    required DateTime ticketTime,
  }) async {
    final branch = await _db.getBranch(branchId);

    if (branch == null) {
      throw Exception("That branch is no longer listed.");
    }

    final film = await filmDetails(filmId);
    final ad = await adMinutes(branch.cinemaName, film.durationMin);
    final breaks = await breaksForFilm(filmId);

    return Schedule(
      branch: branch,
      film: film,
      ticketTime: ticketTime,
      adMinutes: ad,
      breaks: breaks,
    );
  }

  /// How long a "found nothing" answer is trusted before the film is
  /// worth asking about again.
  ///
  /// Only empty answers expire. A film Gemini actually described is
  /// described correctly forever — its scenes do not move — so those
  /// are never re-asked and cost one API call for all time.
  ///
  /// Empty answers are different: the prompt tells Gemini to decline
  /// rather than guess, and it declines most for films it has no
  /// scene-level knowledge of — a regional release in its opening
  /// week, say. That is a statement about what the model knew on the
  /// day it was asked, not about the film, and it stops being true as
  /// a film becomes better known. Caching it permanently would mean a
  /// film that happened to be new when the first person opened it
  /// never gets breaks at all.
  static const Duration _reAskEmptyAfter = Duration(days: 7);

  /// Cache first, Gemini on a miss.
  ///
  /// `breaks_checked_at` is what separates the two: a film that carries
  /// a timestamp has been asked about already, and whatever `breaks`
  /// rows exist are the answer. Only a film that has never been asked
  /// about — or whose empty answer has gone stale, see
  /// [_reAskEmptyAfter] — reaches Gemini, and the answer is written
  /// straight back, so the next person to open that film (any user,
  /// any device) gets it from the table.
  @override
  Future<List<FilmBreak>> breaksForFilm(int filmId) async {
    final film = await filmDetails(filmId);

    // `creditSceneChecked` joins `breaksAreCached` as a condition of the
    // cache being complete. A row written before `credit_scene_start_min`
    // existed is stamped but has nothing in that column, and would
    // otherwise never learn whether its film has a credits scene — the
    // stamp alone would keep it away from Gemini forever. Letting those
    // fall through re-asks each such film exactly once, on the next open;
    // the answer then fills the column (with a real minute or the "no
    // scene" sentinel) and it is never re-asked on this account again.
    if (film.breaksAreCached && film.creditSceneChecked) {
      // Keyed on the movie: every cinema listing it shares one answer.
      final cached = await _db.getBreaks(film.movieId);

      // A real answer. Never expires, never re-asked.
      //
      // Capped on the way out, because films cached before the limit
      // dropped to two can hold up to four rows. Trimming here fixes
      // them on screen without a paid re-ask.
      if (cached.isNotEmpty) {
        return cached.take(GeminiApi.maxBreaks).toList();
      }

      // "Asked, found nothing" — honour it until it goes stale.
      final age = DateTime.now().difference(film.breaksCheckedAt!);
      if (age < _reAskEmptyAfter) {
        return cached;
      }
      // Stale empty answer: fall through and ask again.
    }

    // Nothing to ask about: Gemini is given a title and a runtime, and
    // the runtime is what every minute in the answer is validated
    // against. Don't stamp the film either — the runtime may well be
    // scraped tomorrow, and then it is worth asking.
    if (!film.hasKnownDuration) {
      return const [];
    }

    // One call. Gemini answers from the film's real scenes when it knows
    // them and reasons from its runtime and likely pacing when it
    // doesn't, and says which in its reply — stored as `is_estimated`
    // so the screen can label the second kind.
    final answer = await _gemini.getBreaksForFilm(film.title, film.durationMin);

    // Rows first, then the stamp. The stamp is what the next reader
    // trusts, so it must not be newer than the rows it vouches for: if
    // writing the breaks fails, the film stays unstamped and is simply
    // asked again, rather than being marked "checked, nothing found"
    // for a week because one of two writes didn't land.
    //
    // addNewBreaks replaces rather than appends, so a re-ask that now
    // has an answer cleanly overwrites the empty one.
    await _db.addNewBreaks(film.movieId, answer.breaks);
    await _db.markBreaksChecked(film.movieId, answer.creditsStartMin, answer.creditSceneStartMin);

    return answer.breaks;
  }

  // ---- Showtimes ------------------------------------------------------------

  @override
  Future<List<Showtime>> showtimesForFilm(int filmId) => _db.getShowtimesForFilm(filmId);

  @override
  Future<List<UpcomingShowtime>> startingSoon() => _db.getStartingSoon();

  // ---- Attendance -----------------------------------------------------------

  @override
  Future<int> recordAttendance(Schedule schedule) async {
    final userId = _requireUserId();

    return _db.addNewMovieSeen(
      userId,
      schedule.branch.id,
      schedule.film.filmId,
      schedule.ticketTime,
    );
  }

  // ---- History -------------------------------------------------------------

  @override
  Future<List<Attendance>> history() async {
    final userId = _db.supabase.auth.currentUser?.id;

    // Signed out is not an error here — the splash screen sends a
    // signed-out person to auth, and a screen that asks anyway should
    // render "nothing yet", not throw.
    if (userId == null) {
      return const [];
    }
    return _db.getHistory(userId);
  }

  @override
  Future<YearlyRecap> recap(int year) async {
    final userId = _db.supabase.auth.currentUser?.id;

    if (userId == null) {
      return YearlyRecap(
        year: year,
        filmsWatched: 0,
        cinemasVisited: 0,
        totalAdMinutes: 0,
        totalWatchMinutes: 0,
      );
    }
    return _db.getRecap(userId, year);
  }

  /// Writing attendance, unlike reading history, genuinely cannot be
  /// done signed out — RLS would reject the insert anyway, and this
  /// says so in a sentence rather than as a Postgres error.
  String _requireUserId() {
    final userId = _db.supabase.auth.currentUser?.id;

    if (userId == null) {
      throw Exception("Sign in to save a screening to your history.");
    }
    return userId;
  }
}
