/// One cinema's listing of a film — a row of `films`, carrying its own
/// Gemini answers (`credits_start_min`, `breaks_checked_at`) directly.
///
/// There used to be a separate `movies` table shared across chains, so
/// VOX's and Muvi's listings of the same title asked Gemini once between
/// them (see the old scripts/add_movies_table.sql). That table has been
/// dropped — each cinema's listing now caches its own answer, so the
/// same title showing at two chains asks Gemini twice. Simpler, at that
/// cost.
///
/// `breaksCheckedAt` is the two-state-encodes-three-outcomes column from
/// the proposal: null means never asked; non-null with no [FilmBreak]
/// rows means asked and nothing usable was found.
class Film {
  const Film({
    required this.filmId,
    required this.movieId,
    required this.title,
    required this.durationMin,
    this.source,
    this.sourceSlug,
    this.posterUrl,
    this.creditsStartMin,
    this.creditSceneStartMin,
    this.breaksCheckedAt,
  });

  /// A `films` row, ideally with its movie embedded — queried as
  /// `select("*, movies(*)")`. Without the embed (history rows don't need
  /// it) the credits and checked-at simply come through null; nothing
  /// that reads history uses them.
  factory Film.fromJson(Map<String, dynamic> json) {
    final checkedAt = json["breaks_checked_at"];

    return Film(
      filmId: json["film_id"],
      // No separate `movies` table any more — this listing's own row is
      // what breaks/credits are cached against, so this is just filmId.
      movieId: json["film_id"],
      title: json["title"],
      // `duration_min` is nullable in the schema — VOX leaves the
      // runtime off titles that haven't opened yet. 0 carries that
      // through as "unknown", which [hasKnownDuration] reads.
      durationMin: json["duration_min"] ?? 0,
      source: json["source"],
      sourceSlug: json["source_slug"],
      posterUrl: json["poster_url"],
      creditsStartMin: json["credits_start_min"],
      creditSceneStartMin: json["credit_scene_start_min"],
      breaksCheckedAt: checkedAt == null ? null : DateTime.parse(checkedAt).toLocal(),
    );
  }

  /// This cinema's listing.
  final int filmId;

  /// Breaks/credits are cached against this — equal to [filmId] now
  /// that there is no separate `movies` table (see the class doc).
  final int movieId;

  final String title;
  final int durationMin;

  /// Which cinema's site this film was scraped from ('vox'), and that
  /// site's own slug for it ('the-odyssey'). Together they're the
  /// film's identity at the source, which is what [bookingUrl] rebuilds
  /// a link out of. Null only for a row written before the scraper
  /// existed.
  final String? source;
  final String? sourceSlug;
  final String? posterUrl;
  /// When the end credits begin. Informational — "the film is over, you
  /// can go". Null when unknown.
  final int? creditsStartMin;

  /// When the mid/post-credits scene plays — the one worth staying for.
  /// Three states, deliberately, the same shape [breaksCheckedAt] uses
  /// (see scripts/add_credit_scene_to_films.sql):
  ///
  ///   null              never asked — [creditSceneChecked] is false and
  ///                     the film is re-asked next time it is opened.
  ///   == durationMin    asked; this film has no credits scene.
  ///   <  durationMin    asked; the scene is at that minute.
  ///
  /// Read it through [hasCreditScene] rather than comparing by hand.
  final int? creditSceneStartMin;

  final DateTime? breaksCheckedAt;

  /// Used to attach Gemini's credits answer to the cached row before
  /// writing it back — Gemini is only ever asked for the credits/break
  /// timing, never for title/duration/poster, so those three pass
  /// through untouched here.
  Film copyWith({int? creditsStartMin, int? creditSceneStartMin, DateTime? breaksCheckedAt}) {
    return Film(
      filmId: filmId,
      movieId: movieId,
      title: title,
      durationMin: durationMin,
      source: source,
      sourceSlug: sourceSlug,
      posterUrl: posterUrl,
      creditsStartMin: creditsStartMin ?? this.creditsStartMin,
      creditSceneStartMin: creditSceneStartMin ?? this.creditSceneStartMin,
      breaksCheckedAt: breaksCheckedAt ?? this.breaksCheckedAt,
    );
  }

  /// Where each scraped site's own film page lives, as a template the
  /// slug is substituted into. The scraper builds the very same URL to
  /// read the runtime and poster off (`f"{BASE}/movies/{slug}"` in
  /// vox_scraper.py), so a link built here lands on the page the row
  /// came from — the one with that cinema's own booking flow on it.
  /// Adding a chain is one line here — the key is the `films.source`
  /// token its scraper stamps rows with, the value is everything before
  /// the slug. Take both from the scraper itself rather than from a
  /// browser's address bar: the scraper already has to build this exact
  /// URL to read the film's page, so its `BASE` and its slug are the
  /// two halves that are known to work together.
  ///
  /// The other four chains are deliberately absent rather than guessed.
  /// A wrong template here would send someone to a 404 on a cinema's
  /// real site, which is worse than no link — and until their scrapers
  /// exist there are no films with those sources anyway.
  static const Map<String, String> _filmPageBySource = {
    'vox': 'https://ksa.voxcinemas.com/movies/',
    'muvi': 'https://www.muvicinemas.com/en/movies/',
    'cinehouse': 'https://www.cinehousecinema.com/show/',
    'scene': 'https://www.scenecinemas.sa/movies/',
    // 'reel': no confirmed per-film deep link; see reel_scraper.py's docstring.
  };

  /// For chains with no per-film page on record: their own showtimes page,
  /// where the film can still be found and booked. Only real pages go
  /// here — Reel's is the one reel_scraper.py watched to find its feed.
  static const Map<String, String> _chainPageBySource = {
    'reel': 'https://www.reelcinemas.com/en-sa/showtime',
  };

  /// The cinema's own page for this film; failing that, the chain's
  /// showtimes page; or null when neither is on record — in which case no
  /// link is shown rather than a guessed one.
  Uri? get bookingUrl {
    final base = _filmPageBySource[source];
    final slug = sourceSlug;

    if (base != null && slug != null && slug.isNotEmpty) {
      return Uri.parse('$base$slug');
    }
    final chainPage = _chainPageBySource[source];
    return chainPage == null ? null : Uri.parse(chainPage);
  }

  /// Two rows for the same `film_id` are the same film, whichever
  /// query built them. Without this, a film tapped on the Cinemas tab
  /// (from `filmsForCinema`) and the same film in the Schedule Card's
  /// picker (from `nowShowing`) are two unequal objects, and
  /// DropdownButton asserts that its value matches exactly one item.
  @override
  bool operator ==(Object other) => other is Film && other.filmId == filmId;

  @override
  int get hashCode => filmId.hashCode;

  bool get breaksAreCached => breaksCheckedAt != null;

  /// False for a row written before `credit_scene_start_min` existed, or
  /// for a film never opened since. Those are re-asked once; after that
  /// the column holds either a real minute or the "no scene" sentinel,
  /// so a film without a credits scene is never re-asked on its account.
  bool get creditSceneChecked => creditSceneStartMin != null;

  /// True only when this film really has a scene in or after its credits.
  /// The sentinel (== [durationMin]) is "asked, none", not a scene at the
  /// last minute — hence the strict `<`.
  bool get hasCreditScene {
    final start = creditSceneStartMin;
    return start != null && start < durationMin;
  }

  /// False when the source site had no runtime listed yet (VOX leaves
  /// this off for titles that haven't opened) — a schedule cannot be
  /// built from this film until a real duration is known.
  bool get hasKnownDuration => durationMin > 0;
}
