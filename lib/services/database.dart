import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_user.dart';
import '../models/attendance.dart';
import '../models/branch.dart';
import '../models/cinema.dart';
import '../models/film.dart';
import '../models/film_break.dart';
import '../models/showtime.dart';
import '../models/upcoming_showtime.dart';
import '../models/yearly_recap.dart';

/// Everything the app asks of Supabase: auth, and the seven tables.
///
/// `profiles` and `movies_seen` are written only for the signed-in user,
/// which RLS enforces. `cinemas` and `branches` are read-only reference
/// data; `branches` is additionally kept in sync by the VOX scraper for
/// VOX's own branches (see scripts/sync_to_supabase.py).
///
/// `movies` and `breaks` are the shared cache: any signed-in user may
/// write them, and every user reads what anyone else filled in. That is
/// deliberate — a movie's safe windows are the same for
/// everyone, at every cinema, so asking Gemini once per movie rather than once per person
/// is the whole point. It does mean the rows are only as trustworthy as
/// the app writing them, which is why [GeminiApi] validates hard before
/// anything reaches [markBreaksChecked] or [addNewBreaks].
///
/// `showtimes` is read-only from here too, but for a different reason:
/// it is written exclusively by the scraper's service-role key, which
/// bypasses RLS entirely, so there is no `addNewShowtime` — nothing in
/// the app is meant to write one.
class Database {
  final supabase = Supabase.instance.client;

  /// There is no separate `movies` table any more — a film row carries
  /// its own credits minute and breaks-checked stamp directly, so a
  /// plain `select()` already has everything [Film.fromJson] needs.
  static const String filmWithMovie = "*";

  // ---- Auth -------------------------------------------------------------

  /// Registers, and stops there. Email confirmation is ON in the
  /// Supabase project, so `signUp` creates the user but returns no
  /// session: nothing in the app is reachable until
  /// [verifySignUpCode] trades the emailed code for one.
  ///
  /// The `profiles` row is created by the `on_auth_user_created`
  /// trigger from the [displayName] passed here, so it already exists
  /// by the time the code is verified and [getProfile] is called.
  Future<void> signUp(String email, String password, String displayName) async {
    AuthResponse response;

    try {
      response = await supabase.auth.signUp(
        email: email,
        password: password,
        data: {"display_name": displayName},
      );
    } catch (error) {
      throw readableAuthError(error);
    }

    final user = response.user;

    // Raised outside the catch above so it isn't rewritten into
    // readableAuthError's generic network message.
    if (user == null) {
      throw Exception("Sign-up didn't complete. Try again.");
    }

    // With confirmation on, Supabase answers an address that is already
    // registered and confirmed with a user carrying an empty identity
    // list rather than an error — deliberately, so the form can't be
    // used to discover who has an account. Telling the person beats
    // parking them on a code screen for an email that will never
    // arrive; delete this to keep that disclosure shut instead.
    if (user.identities?.isEmpty ?? false) {
      throw Exception("An account with that email already exists.");
    }
  }

  /// Trades the emailed sign-up code for a real session, which is what
  /// marks the address confirmed.
  ///
  /// Relies on the dashboard's "Confirm signup" email template printing
  /// `{{ .Token }}` — the stock template only has a link, same as the
  /// reset one.
  Future<AppUser> verifySignUpCode(String email, String code) async {
    try {
      final response = await supabase.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.signup,
      );

      return await getProfile(response.user!.id);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Sends the confirmation code again. Only valid while the account
  /// exists and is still unconfirmed.
  Future<void> resendSignUpCode(String email) async {
    try {
      await supabase.auth.resend(type: OtpType.signup, email: email);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  Future<AppUser> signIn(String email, String password) async {
    try {
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      return await getProfile(response.user!.id);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  Future<void> signOut() async {
    await supabase.auth.signOut();
  }

  /// Deletes the account for good: the `movies_seen` history, the
  /// `profiles` row, and the `auth.users` row itself.
  ///
  /// Goes through the `delete_own_account` SQL function rather than
  /// deleting from here, because removing an auth user needs privileges
  /// the app's publishable key deliberately doesn't have. That function
  /// reads `auth.uid()` itself and takes no arguments, so it can only
  /// ever delete the caller — see scripts/add_delete_account_function.sql,
  /// which has to be run once on the project before this works.
  Future<void> deleteAccount() async {
    try {
      await supabase.rpc("delete_own_account");
    } on PostgrestException catch (error) {
      // PGRST202: PostgREST has no such function in its schema cache, so
      // the call never reached Postgres — which is why this isn't
      // Postgres's own 42883 undefined_function. Either the SQL hasn't
      // been run on this project, or it has and the cache is stale.
      if (error.code == "PGRST202") {
        throw Exception(
          "Account deletion isn't set up on this project yet — run "
          "scripts/add_delete_account_function.sql.",
        );
      }
      // Anything else carries the reason Postgres gave, verbatim. A
      // generic "try again" here is untrue — retrying a permission
      // error or a missing column fails identically every time — and it
      // hides the one detail that says what to fix.
      throw Exception("Couldn't delete your account: ${error.message} (${error.code})");
    } catch (error) {
      throw Exception("Network error — check your connection and try again.");
    }

    // The account is already gone at this point, so a failure to sign
    // out cleanly (the server has no user to log out any more) is not
    // worth surfacing — the local session still has to be cleared.
    try {
      await signOut();
    } catch (_) {}
  }

  /// Emails a one-time reset code — not a link.
  ///
  /// A link would redirect to the project's Site URL (localhost by
  /// default) or need deep-link setup, and with PKCE it only works on the
  /// device that asked for it. A code typed into the app works wherever
  /// the email is read. This relies on the dashboard's "Reset Password"
  /// email template printing `{{ .Token }}`; the stock template only has
  /// the link.
  Future<void> sendPasswordReset(String email) async {
    try {
      await supabase.auth.resetPasswordForEmail(email);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Trades the emailed reset code for a signed-in recovery session, which
  /// is what lets [updatePassword] run next.
  Future<void> verifyResetCode(String email, String code) async {
    try {
      await supabase.auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Sets a new password for the signed-in user — during recovery, the
  /// session [verifyResetCode] just created.
  Future<void> updatePassword(String newPassword) async {
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (error) {
      throw readableAuthError(error);
    }
  }

  /// Turns a Supabase failure into something worth showing a person.
  ///
  /// An [AuthException] prints as `AuthException(message: Invalid login
  /// credentials, statusCode: 400, code: invalid_credentials)`, and the
  /// auth screens put whatever is thrown straight into the error
  /// banner. So each case the user can actually act on gets a sentence,
  /// and anything unrecognised falls back to Supabase's own message
  /// rather than being swallowed.
  Exception readableAuthError(Object error) {
    if (error is! AuthException) {
      return Exception("Network error — check your connection and try again.");
    }

    switch (error.code) {
      case "invalid_credentials":
        return Exception("Incorrect email or password.");
      // Fires when someone abandons the code screen and later tries to
      // sign in — the account exists, the address was never confirmed.
      case "email_not_confirmed":
        return Exception("Confirm your email first — check your inbox for the code.");
      case "user_already_exists":
      case "email_exists":
        return Exception("An account with that email already exists.");
      case "weak_password":
        return Exception("That password is too weak — try a longer one.");
      case "same_password":
        return Exception("That's already your password — choose a different one.");
      // Supabase answers a mistyped code and an expired one the same way.
      case "otp_expired":
        return Exception("That code is wrong or has expired. Check it, or send a new one.");
      case "over_email_send_rate_limit":
      case "over_request_rate_limit":
        return Exception("Too many attempts. Wait a minute, then try again.");
      default:
        return Exception(error.message);
    }
  }

  /// The signed-in person, or null when the session has expired or the
  /// email was never confirmed — what the splash screen decides on.
  Future<AppUser?> getCurrentUser() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      return null;
    }
    return getProfile(user.id);
  }

  Future<AppUser> getProfile(String userId) async {
    final data = await supabase
        .from("profiles")
        .select()
        .eq("profile_id", userId)
        .single();

    return AppUser.fromJson(data);
  }

  Future<void> updateProfile(String userId, String displayName, String? avatarUrl) async {
    await supabase.from("profiles").update({
      "display_name": displayName,
      "avatar_url": avatarUrl,
    }).eq("profile_id", userId);
  }

  /// Uploads a picked profile photo to the `avatars` storage bucket and
  /// returns its public URL - [updateProfile] still has to be called
  /// separately to actually attach that URL to the profile row, same
  /// as with the display name.
  ///
  /// Requires a public `avatars` bucket to already exist in the
  /// Supabase project (Storage -> New bucket, name it exactly
  /// "avatars", mark it public) with storage.objects policies letting
  /// a signed-in user read anything in it and write only inside a
  /// folder named after their own uid - the upload path below
  /// ($userId/avatar.ext) is written to match a policy shaped like:
  ///   using/with check: bucket_id = 'avatars'
  ///     and auth.uid()::text = (storage.foldername(name))[1]
  /// Without that bucket and those policies this throws a
  /// StorageException, which the caller shows as a plain error rather
  /// than crashing.
  Future<String> uploadAvatar(String userId, File file) async {
    final ext = file.path.contains('.') ? file.path.split('.').last.toLowerCase() : 'jpg';
    final path = '$userId/avatar.$ext';

    await supabase.storage.from('avatars').upload(
          path,
          file,
          fileOptions: const FileOptions(upsert: true),
        );

    // Cache-busted so the newly uploaded photo shows immediately - an
    // upsert to the same path would otherwise keep the same URL a
    // NetworkImage may have already cached from the old photo.
    final publicUrl = supabase.storage.from('avatars').getPublicUrl(path);
    return '$publicUrl?updated=${DateTime.now().millisecondsSinceEpoch}';
  }

  // ---- Cinemas and branches ---------------------------------------------

  Future<List<Cinema>> getAllCinemas() async {
    final data = await supabase.from("cinemas").select().order("cinema_name");

    List<Cinema> allCinemas = [];

    for (var element in data) {
      Cinema cinema = Cinema.fromJson(element);
      allCinemas.add(cinema);
    }
    return allCinemas;
  }

  /// One branch by its id — what [SupabaseRepository.buildSchedule]
  /// needs to turn a `branch_id` back into a chain and a place.
  Future<Branch?> getBranch(int branchId) async {
    final data = await supabase
        .from("branches")
        .select()
        .eq("branch_id", branchId)
        .maybeSingle();

    if (data == null) {
      return null;
    }
    return Branch.fromJson(data);
  }

  Future<List<Branch>> getBranches(String cinemaName) async {
    final data = await supabase
        .from("branches")
        .select()
        .eq("cinema_name", cinemaName)
        .order("branch_name");

    List<Branch> allBranches = [];

    for (var element in data) {
      Branch branch = Branch.fromJson(element);
      allBranches.add(branch);
    }
    return allBranches;
  }

  // ---- Films and breaks (the shared cache) ------------------------------

  /// Everything the scrapers have mirrored, by title — the
  /// film picker on the Schedule Card. Titles with no runtime yet are
  /// included: the picker shows them, and `Film.hasKnownDuration` is
  /// what stops a schedule being built from one.
  Future<List<Film>> getNowShowing() async {
    final data = await supabase.from("films").select(filmWithMovie).order("title");

    List<Film> allFilms = [];

    for (var element in data) {
      allFilms.add(Film.fromJson(element));
    }
    return allFilms;
  }

  /// Films whose title contains [query], for matching a title read off
  /// a ticket. `ilike` is Postgres' case-insensitive LIKE, so the
  /// wildcards do the fuzzy part — a short or garbled OCR guess still
  /// finds "Spider-Man: Brand New Day" from "spider".
  Future<List<Film>> searchFilmsByTitle(String query) async {
    final data = await supabase
        .from("films")
        .select(filmWithMovie)
        .ilike("title", "%$query%")
        .order("title");

    List<Film> matches = [];

    for (var element in data) {
      matches.add(Film.fromJson(element));
    }
    return matches;
  }

  /// The cached film, or null when this film has never been mirrored
  /// — in which case the Edge Function has to run before a schedule can
  /// be built.
  Future<Film?> getFilm(int filmId) async {
    final data = await supabase
        .from("films")
        .select(filmWithMovie)
        .eq("film_id", filmId)
        .maybeSingle();

    if (data == null) {
      return null;
    }
    return Film.fromJson(data);
  }

  /// The safe windows for a film. An empty list is ambiguous on its own
  /// — it means either "never asked" or "asked, found nothing" — so
  /// read `Film.breaksAreCached` to tell those apart.
  ///
  /// Keyed on the film's own row — there is no shared `movies` table any
  /// more, so two chains listing the same title cache separately.
  Future<List<FilmBreak>> getBreaks(int movieId) async {
    final data = await supabase
        .from("breaks")
        .select()
        .eq("film_id", movieId)
        .order("start_min");

    List<FilmBreak> allBreaks = [];

    for (var element in data) {
      FilmBreak filmBreak = FilmBreak.fromJson(element);
      allBreaks.add(filmBreak);
    }
    return allBreaks;
  }

  /// Stamps this film's listing as checked once Gemini has answered for
  /// it, and stores the two minutes it found: when the credits roll, and
  /// when the credits scene plays (or the "no scene" sentinel — see
  /// [Film.creditSceneStartMin]).
  ///
  /// [creditSceneStartMin] must be non-null here even when the film has
  /// no scene, because null in that column means "never asked" and would
  /// send this same film back to Gemini on the next open.
  ///
  /// `breaks_checked_at` is set here rather than by the caller, because
  /// stamping it is what makes the cache a cache: a non-null timestamp
  /// with no `breaks` rows means "asked Gemini, found nothing", and is
  /// what stops the same film being sent to Gemini over and over.
  ///
  /// Written to `films` directly — there is no separate `movies` table
  /// any more, so each chain's listing of a title stamps its own row.
  Future<void> markBreaksChecked(
    int movieId,
    int? creditsStartMin,
    int? creditSceneStartMin,
    int? creditSceneEndMin,
  ) async {
    await supabase.from("films").update({
      "credits_start_min": creditsStartMin,
      "credit_scene_start_min": creditSceneStartMin,
      "credit_scene_end_min": creditSceneEndMin,
      "breaks_checked_at": DateTime.now().toUtc().toIso8601String(),
    }).eq("film_id", movieId);
  }

  /// Caches the safe windows for a film. Call [markBreaksChecked] too.
  Future<void> addNewBreaks(int movieId, List<FilmBreak> breaks) async {
    // Replace rather than append: re-asking Gemini for a film must not
    // trip the (film_id, start_min) primary key.
    await supabase.from("breaks").delete().eq("film_id", movieId);

    // Nothing found is a real answer, and the stamp on `films` already
    // recorded it. No rows to write.
    if (breaks.isEmpty) {
      return;
    }

    List<Map<String, dynamic>> rows = [];

    for (var filmBreak in breaks) {
      rows.add({
        "film_id": movieId,
        "start_min": filmBreak.startMin,
        "end_min": filmBreak.endMin,
        "is_estimated": filmBreak.isEstimated,
      });
    }
    await supabase.from("breaks").insert(rows);
  }

  // ---- Showtimes (read-only — written only by the scraper) --------------

  /// Every showing of [filmId] across all branches, soonest first.
  Future<List<Showtime>> getShowtimesForFilm(int filmId) async {
    final data = await supabase
        .from("showtimes")
        .select()
        .eq("film_id", filmId)
        .order("show_time");

    List<Showtime> allShowtimes = [];

    for (var element in data) {
      allShowtimes.add(Showtime.fromJson(element));
    }
    return allShowtimes;
  }

  /// The soonest showtimes across every chain and branch, film and
  /// branch already resolved — for the Home screen'''s "Starting Soon"
  /// row. Unlike [getFilmsBySource], this one DOES join through to
  /// `branches`: Home wants the chain and branch name to show next to
  /// each time, not just which chain a film came from, and a branch
  /// with no `source`/`source_code` filled in yet simply has no
  /// showtimes to join against, so it never appears here rather than
  /// appearing with a blank branch name.
  ///
  /// Only showtimes still ahead of now are returned - nothing here
  /// tells someone to run for a screening that already started.
  Future<List<UpcomingShowtime>> getStartingSoon({int limit = 12}) async {
    // `order()` on this client defaults to ascending: false (newest/latest
    // first) - without `ascending: true` this was returning the LATEST
    // showtimes instead of the soonest ones, which is why the Home screen
    // was showing a showtime days away as if it were "starting soon".
    //
    // We also fetch more rows than we need and keep only the first (i.e.
    // earliest, since the query is ascending) showtime per film, so one
    // popular movie with many showtimes right now can't fill the whole
    // section - the list stays one row per film, soonest first.
    final data = await supabase
        .from("showtimes")
        .select("*, films(*), branches(*)")
        .gte("show_time", DateTime.now().toUtc().toIso8601String())
        .order("show_time", ascending: true)
        .limit(limit * 4);

    final upcoming = <UpcomingShowtime>[];
    final seenFilmIds = <int>{};

    for (var element in data) {
      final showtime = UpcomingShowtime.fromJson(element);
      if (!seenFilmIds.add(showtime.filmId)) continue;
      upcoming.add(showtime);
      if (upcoming.length >= limit) break;
    }
    return upcoming;
  }

  /// Every film scraped from one chain's own site — the Cinemas tab's
  /// per-chain row. [source] is the `films.source` token the scraper
  /// stamps each row with ('vox'), which is the direct record of whose
  /// listings a film came from.
  ///
  /// Deliberately *not* joined through `showtimes` → `branches`, which
  /// would look like the more correct question to ask. `branches` is
  /// hand-managed: sync_to_supabase.py only reads it, matching VOX's
  /// own branch codes against `source_code` values someone has to
  /// enter by hand, and silently skips the showtimes of any branch
  /// with no matching row. Until those rows exist, `showtimes` is
  /// empty and that join returns nothing for films that are plainly
  /// in the table. `source` is populated by the same upsert that
  /// writes the film, so it is true the moment a film exists.
  Future<List<Film>> getFilmsBySource(String source) async {
    final data = await supabase
        .from("films")
        .select(filmWithMovie)
        .eq("source", source)
        .order("title");

    List<Film> allFilms = [];

    for (var element in data) {
      allFilms.add(Film.fromJson(element));
    }
    return allFilms;
  }

  // ---- Movies seen ------------------------------------------------------

  /// Writes the inputs that produced a schedule, never the schedule
  /// itself. Returns the new `movie_seen_id`.
  Future<int> addNewMovieSeen(
    String userId,
    int branchId,
    int filmId,
    DateTime ticketTime,
  ) async {
    final data = await supabase
        .from("movies_seen")
        .insert({
          "user_id": userId,
          "branch_id": branchId,
          "film_id": filmId,
          "ticket_time": ticketTime.toUtc().toIso8601String(),
        })
        .select("movie_seen_id")
        .single();

    return data["movie_seen_id"];
  }

  /// One round trip for the History screen. The nested select tells
  /// PostgREST to embed the related rows through the foreign keys, so
  /// each entry arrives with its branch, that branch's chain, and the
  /// film already attached.
  Future<List<Attendance>> getHistory(String userId) async {
    final data = await supabase
        .from("movies_seen")
        .select("*, branches(*, cinemas(*)), films(*)")
        .eq("user_id", userId)
        .order("ticket_time", ascending: false);

    List<Attendance> allSeen = [];

    for (var element in data) {
      Attendance attendance = Attendance.fromJson(element);
      allSeen.add(attendance);
    }
    return allSeen;
  }

  /// The recap card's figures for one year, summed on the device from
  /// the same embedded rows [getHistory] returns.
  Future<YearlyRecap> getRecap(String userId, int year) async {
    final data = await supabase
        .from("movies_seen")
        .select("*, branches(*, cinemas(*)), films(*)")
        .eq("user_id", userId)
        .gte("ticket_time", DateTime.utc(year).toIso8601String())
        .lt("ticket_time", DateTime.utc(year + 1).toIso8601String());

    int totalAdMinutes = 0;
    int totalWatchMinutes = 0;
    Set<String> cinemasVisited = {};

    for (var element in data) {
      Attendance attendance = Attendance.fromJson(element);
      totalAdMinutes += attendance.adMinutes;
      totalWatchMinutes += attendance.durationMin;
      cinemasVisited.add(attendance.cinemaName);
    }

    return YearlyRecap(
      year: year,
      filmsWatched: data.length,
      cinemasVisited: cinemasVisited.length,
      totalAdMinutes: totalAdMinutes,
      totalWatchMinutes: totalWatchMinutes,
    );
  }
}
