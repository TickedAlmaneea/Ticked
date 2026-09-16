import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/cinema.dart';
import '../../models/film.dart';
import '../../widgets/film_poster_card.dart';
import '../../widgets/vignette_backdrop.dart';
import '../schedule/schedule_card_screen.dart';

/// One request to scroll the Cinemas tab to a named chain, raised by
/// Home's "browse by cinema" chips. [seq] exists so two taps on the
/// same chip are two distinct values — a plain `String?` notifier would
/// swallow the second.
class CinemaJumpRequest {
  const CinemaJumpRequest(this.cinemaName, this.seq);

  final String cinemaName;
  final int seq;
}

/// The tab that replaced History — one horizontally scrollable row of
/// films per chain, five rows down the page.
///
/// VOX and Muvi are scraped today ([SupabaseRepository.filmsForCinema]
/// returns nothing for the other three), so those two rows show real
/// listings and the rest show the empty state; the mirroring lives in
/// the repository, not here, so this screen needs no change once the
/// remaining scrapers land.
class CinemasScreen extends StatefulWidget {
  const CinemasScreen({super.key, this.jumpTo});

  /// Set by [MainShell] when Home asks to open this tab at a chain.
  final ValueListenable<CinemaJumpRequest?>? jumpTo;

  @override
  State<CinemasScreen> createState() => _CinemasScreenState();
}

class _CinemasScreenState extends State<CinemasScreen> {
  /// Display order for the chain rows on this screen, top to bottom.
  /// Anything not listed here (a new chain not yet accounted for)
  /// sorts after all of these rather than disappearing.
  static const List<String> _chainOrder = ['VOX', 'Reel', 'Muvi', 'CINEHOUSE', 'Scene'];

  List<Cinema> _ordered(List<Cinema> cinemas) {
    final sorted = List<Cinema>.of(cinemas);
    sorted.sort((a, b) {
      final ai = _chainOrder.indexOf(a.name);
      final bi = _chainOrder.indexOf(b.name);
      return (ai == -1 ? _chainOrder.length : ai).compareTo(bi == -1 ? _chainOrder.length : bi);
    });
    return sorted;
  }

  late Future<List<Cinema>> _cinemas;

  /// Per-chain, so one chain's slow load never blanks the others.
  final Map<String, Future<List<Film>>> _filmsByCinema = {};

  /// Anchors for [CinemaJumpRequest] — one per chain section.
  final Map<String, GlobalKey> _sectionKeys = {};

  @override
  void initState() {
    super.initState();
    _cinemas = appRepository.cinemas();
    widget.jumpTo?.addListener(_onJumpRequested);
  }

  @override
  void dispose() {
    widget.jumpTo?.removeListener(_onJumpRequested);
    super.dispose();
  }

  void _onJumpRequested() {
    final request = widget.jumpTo?.value;
    if (request == null) return;

    // The tab has only just been switched to, so its sections may not
    // have a context to scroll to until this frame is done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _sectionKeys[request.cinemaName]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    });
  }

  Future<List<Film>> _filmsFor(String cinemaName) {
    return _filmsByCinema.putIfAbsent(
      cinemaName,
      () => appRepository.filmsForCinema(cinemaName),
    );
  }

  Future<void> _openFilm(Film film, String cinemaName) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleCardScreen(preselectedFilm: film, preselectedCinemaName: cinemaName),
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
                _cinemas = appRepository.cinemas();
                _filmsByCinema.clear();
              });
              await _cinemas;
            },
            child: FutureBuilder<List<Cinema>>(
              future: _cinemas,
              builder: (context, snapshot) {
                final cinemas = snapshot.data;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(0, 24, 0, 32),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cinemas', style: AppTypography.displayMedium),
                          const SizedBox(height: 4),
                          Text('What is playing at each chain in Riyadh', style: AppTypography.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (cinemas == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 48),
                        child: Center(child: CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2)),
                      )
                    else
                      for (final cinema in _ordered(cinemas))
                        _CinemaRow(
                          key: _sectionKeys.putIfAbsent(cinema.name, GlobalKey.new),
                          cinema: cinema,
                          filmsFuture: _filmsFor(cinema.name),
                          onOpenFilm: (film) => _openFilm(film, cinema.name),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _CinemaRow extends StatelessWidget {
  const _CinemaRow({
    super.key,
    required this.cinema,
    required this.filmsFuture,
    required this.onOpenFilm,
  });

  final Cinema cinema;
  final Future<List<Film>> filmsFuture;
  final ValueChanged<Film> onOpenFilm;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            // Chain name only. The researched ad minutes are the thing
            // the app is for — they stay behind a ticket, never on a
            // browse screen.
            child: Text(
              cinema.name.toUpperCase(),
              style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 12),
          // 132-wide poster at 2:3 is 198 tall, plus the title and
          // duration lines under it — 190 clipped them.
          SizedBox(
            height: 252,
            child: FutureBuilder<List<Film>>(
              future: filmsFuture,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  // TEMP DIAGNOSTIC: surfaces the real error instead of an
                  // endless spinner. Remove once the cause is found.
                  // ignore: avoid_print
                  print('filmsFuture error for ${cinema.name}: ${snapshot.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '${cinema.name} error: ${snapshot.error}',
                        style: AppTypography.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
                  );
                }
                final films = snapshot.data!;
                if (films.isEmpty) {
                  return const _NoListingsYet();
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: films.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => FilmPosterCard(
                    film: films[i],
                    onTap: () => onOpenFilm(films[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown for a chain that is not scraped yet. Reachable today only if
/// the repository stops mirroring VOX's films.
class _NoListingsYet extends StatelessWidget {
  const _NoListingsYet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text('No listings yet for this chain.', style: AppTypography.bodyMedium),
      ),
    );
  }
}
