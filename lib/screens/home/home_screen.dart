import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/app_user.dart';
import '../../models/film.dart';
import '../../models/upcoming_showtime.dart';
import '../../services/database.dart';
import '../../utils/date_format.dart';
import '../../widgets/film_poster_card.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';
import '../schedule/schedule_card_screen.dart';
import '../ticket/upload_ticket_screen.dart';

/// Proposal screen 5 — "Upload your ticket" as the primary action, a
/// "starting soon" list of the very next showings, and a "now showing"
/// carousel pulled straight from the five scraped chains.
///
/// The "most recent session" card that used to sit here is gone — with
/// five chains now syncing real films and showtimes, the home screen
/// has enough of its own data to lead with (starting soon, now
/// showing) rather than a single latest ticket. A personal recap card
/// briefly lived here too; removed since it read badly for a
/// first-time user with nothing tracked yet.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Film>> _nowShowing;
  late Future<List<UpcomingShowtime>> _startingSoon;
  late Future<AppUser?> _currentUser;

  @override
  void initState() {
    super.initState();
    _nowShowing = appRepository.nowShowing();
    _startingSoon = appRepository.startingSoon();
    _currentUser = _loadCurrentUser();
  }

  /// Not signed in resolves to null (see Database.getCurrentUser); a
  /// slow or unreachable Supabase is caught here too, the same
  /// defensive shape ProfileScreen already uses around this same call
  /// - either way the greeting below just falls back to the plain
  /// tagline rather than the whole page breaking over a missing name.
  Future<AppUser?> _loadCurrentUser() async {
    try {
      return await Database().getCurrentUser();
    } catch (_) {
      return null;
    }
  }

  Future<void> _openUploadTicket() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadTicketScreen()));
  }

  /// Which chain a `films.source` token displays as — the inverse of
  /// [SupabaseRepository]'s own map, needed here because [nowShowing]
  /// mixes all five chains together and [ScheduleCardScreen] wants the
  /// cinema's display name, not its source token.
  static const Map<String, String> _cinemaNameBySource = {
    'vox': 'VOX',
    'muvi': 'Muvi',
    'reel': 'Reel',
    'cinehouse': 'CINEHOUSE',
    'scene': 'Scene',
  };

  Future<void> _openFilm(Film film) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleCardScreen(
          preselectedFilm: film,
          preselectedCinemaName: _cinemaNameBySource[film.source],
        ),
      ),
    );
  }

  /// A "Starting Soon" row only has the film's id, not the [Film]
  /// itself — one extra read before the same push [_openFilm] does,
  /// now with the exact showing's own time and branch preselected too.
  Future<void> _openStartingSoon(UpcomingShowtime showtime) async {
    final film = await appRepository.filmDetails(showtime.filmId);
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleCardScreen(
          preselectedFilm: film,
          preselectedCinemaName: showtime.cinemaName,
          preselectedBranchId: showtime.branchId,
          initialTicketTime: showtime.time,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: () async {
              setState(() {
                _nowShowing = appRepository.nowShowing();
                _startingSoon = appRepository.startingSoon();
                _currentUser = _loadCurrentUser();
              });
              await Future.wait([_nowShowing, _startingSoon, _currentUser]);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Text('TICKED', style: AppTypography.displaySmall.copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 4),
                FutureBuilder<AppUser?>(
                  future: _currentUser,
                  builder: (context, snapshot) {
                    final displayName = snapshot.data?.displayName.trim();
                    final firstName = (displayName != null && displayName.isNotEmpty)
                        ? displayName.split(RegExp(r'\s+')).first
                        : null;
                    return Text(
                      firstName != null ? 'Welcome, $firstName' : 'Never miss the first frame',
                      style: AppTypography.displayMedium,
                    );
                  },
                ),
                const SizedBox(height: 22),
                _UploadTicketCard(onTap: _openUploadTicket),
                const SizedBox(height: 30),
                Text('NOW SHOWING', style: AppTypography.overline),
                const SizedBox(height: 12),
                _NowShowingSection(nowShowingFuture: _nowShowing, onOpenFilm: _openFilm),
                const SizedBox(height: 30),
                Text('STARTING SOON', style: AppTypography.overline),
                const SizedBox(height: 12),
                _StartingSoonSection(startingSoonFuture: _startingSoon, onOpenShowtime: _openStartingSoon),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadTicketCard extends StatelessWidget {
  const _UploadTicketCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.confirmation_number_outlined, color: AppColors.gold, size: 26),
          const SizedBox(height: 12),
          Text('Got a ticket?', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Upload the photo and we\'ll tell you when it really starts.',
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 16),
          TickedPrimaryButton(label: 'Upload your ticket', onPressed: onTap),
        ],
      ),
    );
  }
}

/// Normalizes a scraped title for duplicate-detection. A plain
/// `toLowerCase().trim()` only catches identical strings, but five
/// independently-scraped sites describe the same movie with small,
/// ever-changing differences — punctuation ("Avengers: Doomsday" vs
/// "Avengers - Doomsday"), bracketed format/edition tags ("(3D)",
/// "(IMAX)", "(Arabic Subtitled)"), or the same tag written as a plain
/// trailing word instead of in brackets. This strips all of that down
/// to just the words of the title so those still collapse to one row —
/// deliberately general rather than a list of today's movie names, so
/// it keeps working as the lineup changes.
String _normalizedTitle(String title) {
  var normalized = title.toLowerCase();

  // Drop anything in parentheses/brackets - almost always a
  // format/edition/language tag, not part of the movie's name.
  normalized = normalized.replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), ' ');

  // Strip the same kind of tag when it shows up as a plain word
  // instead of in brackets, e.g. "Avengers: Doomsday 3D".
  const tagWords = {
    '3d', '2d', '4d', '4dx', 'imax', 'imax3d', 'dolby', 'atmos',
    'screenx', 'vip', 'gold', 'dubbed', 'subtitled', 'subbed',
    'arabic', 'english', 'original', 'version',
  };

  final words = normalized
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty && !tagWords.contains(word))
      .join(' ')
      .trim();

  // If a title happened to be made up entirely of tag-like words,
  // stripping them all would leave two different films sharing an
  // empty key - fall back to the plain lowercased title instead of
  // ever merging on nothing.
  if (words.isEmpty) return title.trim().toLowerCase();
  return words;
}

/// A horizontal carousel of real posters pulled from every scraped
/// chain (VOX, Muvi, Reel, CINEHOUSE, Scene) — [FilmPosterCard] was
/// already built for exactly this spot on Home, just never wired up
/// until now. Titles with no runtime listed yet are left out, the same
/// filter each sync script applies before writing a film row.
class _NowShowingSection extends StatelessWidget {
  const _NowShowingSection({required this.nowShowingFuture, required this.onOpenFilm});

  final Future<List<Film>> nowShowingFuture;
  final ValueChanged<Film> onOpenFilm;

  /// Enough to fill the row with variety across all five chains
  /// without turning Home into the full Cinemas tab.
  static const int _maxShown = 20;

  /// Since each chain caches its own copy of a film (there is no
  /// shared `movies` table any more — see film.dart's own doc comment),
  /// the same title showing at three chains is three separate rows
  /// here. Fine for the Cinemas tab, where each chain gets its own
  /// section, but redundant-looking crammed into one Home carousel —
  /// so this keeps one entry per movie.
  ///
  /// An exact (normalized) title match isn't enough on its own: one
  /// chain listed the same movie as just "Sunray" while another spelled
  /// out "Sunray: Fallen Soldier", so those two never shared a key.
  /// [_sameFilmTitle] additionally treats one title as the same movie
  /// as another when its words are a leading prefix of the other's —
  /// covering a short/working title next to its fuller counterpart —
  /// and the kept copy is whichever has a poster, or failing that the
  /// longer (more descriptive) of the two titles.
  List<Film> _dedupedByTitle(List<Film> films) {
    final kept = <Film>[];
    final keptTokens = <List<String>>[];

    for (final film in films) {
      final tokens = _normalizedTitle(film.title).split(' ');
      final matchIndex = keptTokens.indexWhere((other) => _sameFilmTitle(tokens, other));

      if (matchIndex == -1) {
        kept.add(film);
        keptTokens.add(tokens);
        continue;
      }

      if (_preferredOver(film, kept[matchIndex])) {
        kept[matchIndex] = film;
        keptTokens[matchIndex] = tokens;
      }
    }

    return kept;
  }

  /// True when one title's words are the other's in full, in order,
  /// from the start — e.g. "sunray" vs "sunray fallen soldier" — which
  /// is how a short/working title relates to its fuller release title.
  /// Deliberately word-based rather than a raw substring check, so
  /// "fall" doesn't match inside "fall 2: deadpoint".
  bool _sameFilmTitle(List<String> a, List<String> b) {
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    if (shorter.isEmpty) return false;
    for (var i = 0; i < shorter.length; i++) {
      if (shorter[i] != longer[i]) return false;
    }
    return true;
  }

  bool _preferredOver(Film candidate, Film current) {
    final candidateHasPoster = candidate.posterUrl != null;
    final currentHasPoster = current.posterUrl != null;
    if (candidateHasPoster != currentHasPoster) return candidateHasPoster;
    return candidate.title.trim().length > current.title.trim().length;
  }

  @override
  Widget build(BuildContext context) {
    // Same 252 as the Cinemas tab's own FilmPosterCard row (132-wide
    // poster at 2:3 is 198 tall, plus the title and duration lines
    // under it — anything shorter clips them).
    return SizedBox(
      height: 252,
      child: FutureBuilder<List<Film>>(
        future: nowShowingFuture,
        builder: (context, snapshot) {
          final films = snapshot.data;
          if (films == null) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            );
          }

          final showable = _dedupedByTitle(
            films.where((film) => film.hasKnownDuration).toList(),
          ).take(_maxShown).toList();
          if (showable.isEmpty) {
            return Center(
              child: Text('Nothing scraped yet — check back soon.', style: AppTypography.bodyMedium),
            );
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: showable.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => FilmPosterCard(
              film: showable[i],
              onTap: () => onOpenFilm(showable[i]),
            ),
          );
        },
      ),
    );
  }
}

/// A vertical list of the soonest showings across every chain and
/// branch — name, poster, chain · branch, and start time together,
/// which is more than a poster tile can show, hence a list of rows
/// rather than another carousel. Tapping one opens the Schedule Card
/// with that exact film, branch and time preselected.
class _StartingSoonSection extends StatelessWidget {
  const _StartingSoonSection({required this.startingSoonFuture, required this.onOpenShowtime});

  final Future<List<UpcomingShowtime>> startingSoonFuture;
  final ValueChanged<UpcomingShowtime> onOpenShowtime;

  /// A handful is the point — this is "what's on very soon", not
  /// another full browse list.
  static const int _maxShown = 6;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UpcomingShowtime>>(
      future: startingSoonFuture,
      builder: (context, snapshot) {
        final upcoming = snapshot.data;

        if (upcoming == null) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
            ),
          );
        }

        final shown = upcoming.take(_maxShown).toList();
        if (shown.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Text('Nothing scraped for the next while yet.', style: AppTypography.bodyMedium),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Divider(height: 1, color: AppColors.divider),
                  ),
                _StartingSoonRow(showtime: shown[i], onTap: () => onOpenShowtime(shown[i])),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StartingSoonRow extends StatelessWidget {
  const _StartingSoonRow({required this.showtime, required this.onTap});

  final UpcomingShowtime showtime;
  final VoidCallback onTap;

  static Widget _placeholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface2, AppColors.velvet],
        ),
      ),
      child: const Center(
        child: Icon(Icons.local_movies_outlined, color: AppColors.textTertiary, size: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        showtime.time.year == now.year && showtime.time.month == now.month && showtime.time.day == now.day;
    final when = isToday ? formatClock(showtime.time) : formatDateAndClock(showtime.time);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 42,
                height: 58,
                child: showtime.posterUrl == null
                    ? _placeholder()
                    : Image.network(
                        showtime.posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _placeholder(),
                        loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder(),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    showtime.filmTitle,
                    style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${showtime.cinemaName} · ${showtime.branchName}',
                    style: AppTypography.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(when, style: AppTypography.timerSmall.copyWith(color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}
