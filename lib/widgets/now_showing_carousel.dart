import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/film.dart';

/// Horizontal gap each poster keeps from its neighbour. File-level
/// because both the carousel (deriving its viewport fraction) and the
/// card (setting its own margin) have to agree on it.
const double _cardGap = 8;

/// Home's "Now Showing" — a centre-weighted poster carousel.
///
/// The old version was a flat horizontal strip of 132px cards with the
/// title and runtime stacked under each one. That reads as a catalogue:
/// every title competes equally and none of them is worth looking at.
/// A cinema foyer doesn't work that way — one poster is lit and the rest
/// are in the dark either side of it.
///
/// So: the centred poster is full size and full colour, its neighbours
/// are scaled down and dimmed, and the title/runtime belong to whichever
/// poster is centred rather than being repeated under all of them. That
/// leaves one thing to read instead of twenty, and makes the poster art —
/// the only real imagery the app has — the thing carrying the screen.
class NowShowingCarousel extends StatefulWidget {
  const NowShowingCarousel({
    super.key,
    required this.films,
    required this.onOpenFilm,
  });

  final List<Film> films;
  final ValueChanged<Film> onOpenFilm;

  @override
  State<NowShowingCarousel> createState() => _NowShowingCarouselState();
}

class _NowShowingCarouselState extends State<NowShowingCarousel> {
  /// How tall the poster strip is. Deliberately short of what a poster
  /// "wants": at 348 the strip alone filled the rest of the screen, so
  /// the title under it and everything below — Starting Soon included —
  /// sat past the fold on a phone.
  static const double _stripHeight = 300;

  /// Posters are 2:3. Rather than pick a viewport fraction by eye and let
  /// BoxFit.cover crop whatever doesn't fit, the card's width is derived
  /// from the strip height so the art is shown whole — cropping a poster
  /// is exactly the kind of thing that makes a carousel look careless.
  double _viewportFractionFor(double maxWidth) {
    final cardWidth = (_stripHeight - _cardGap) * 2 / 3;
    final fraction = (cardWidth + _cardGap * 2) / maxWidth;
    // Guard the extremes: too small and three cards crowd in, too large
    // and the neighbours disappear entirely.
    return fraction.clamp(0.42, 0.78);
  }

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final films = widget.films;
    final current = films[_index.clamp(0, films.length - 1)];

    return Column(
      children: [
        SizedBox(
          height: _stripHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return CarouselSlider.builder(
                itemCount: films.length,
                itemBuilder: (context, index, realIndex) {
                  return _PosterCard(
                    film: films[index],
                    isCentred: index == _index,
                    onTap: () => widget.onOpenFilm(films[index]),
                  );
                },
                options: CarouselOptions(
                  height: _stripHeight,
                  viewportFraction: _viewportFractionFor(constraints.maxWidth),
                  enlargeCenterPage: true,
                  enlargeFactor: 0.28,
                  // A single film would otherwise sit in a scrollable
                  // that rubber-bands against nothing.
                  enableInfiniteScroll: films.length > 2,
                  padEnds: true,
                  // Advances on its own so the row reads as a reel
                  // turning over rather than a static shelf. Only worth
                  // doing when there is somewhere to advance to.
                  autoPlay: films.length > 1,
                  autoPlayInterval: const Duration(seconds: 3),
                  // Slow enough to read as a deliberate move between two
                  // posters rather than a flick.
                  autoPlayAnimationDuration: const Duration(milliseconds: 800),
                  autoPlayCurve: Curves.easeInOutCubic,
                  // Stops fighting the person the moment they take hold
                  // of it; resumes once they let go.
                  pauseAutoPlayOnTouch: true,
                  pauseAutoPlayOnManualNavigate: true,
                  onPageChanged: (index, _) => setState(() => _index = index),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        _CentredCaption(film: current),
        const SizedBox(height: 14),
        _Dots(count: films.length, index: _index),
      ],
    );
  }
}

/// One poster. Dimmed and desaturated when it isn't the centred card, so
/// the eye lands on the middle of the strip rather than wandering.
class _PosterCard extends StatelessWidget {
  const _PosterCard({required this.film, required this.isCentred, required this.onTap});

  final Film film;
  final bool isCentred;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: _cardGap, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            // The centred poster gets the warm hairline; the others get
            // the plain divider, so the highlight reads as focus rather
            // than as decoration on every card.
            color: isCentred ? AppColors.goldDim : AppColors.divider,
            width: isCentred ? 1.5 : 1,
          ),
          boxShadow: isCentred
              ? const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: Offset(0, 12),
                  ),
                ]
              : const [],
        ),
        child: ClipRRect(
          // Inset by the border width so the art doesn't peek past the
          // rounded corner it sits inside.
          borderRadius: BorderRadius.circular(16.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _poster(),
              // A scrim on the off-centre cards. AnimatedOpacity rather
              // than swapping the colour so the two states cross-fade
              // with the scale change instead of snapping.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 280),
                opacity: isCentred ? 0 : 0.55,
                child: const ColoredBox(color: AppColors.bg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster() {
    final url = film.posterUrl;
    if (url == null || url.isEmpty) return _placeholder();

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _placeholder(),
      loadingBuilder: (context, child, progress) => progress == null ? child : _placeholder(),
    );
  }

  Widget _placeholder() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface2, AppColors.velvet],
        ),
      ),
      child: Center(
        child: Icon(Icons.local_movies_outlined, color: AppColors.textTertiary, size: 34),
      ),
    );
  }
}

/// The centred film's title. Fixed height and cross-faded, because a
/// title swapping in at a different length would otherwise shunt the
/// indicator — and the whole section under it — as the carousel turns
/// over, which with autoplay would happen every three seconds unprompted.
///
/// The runtime and chain used to sit under the title. They're gone: the
/// poster is the thing worth looking at, and a stack of grey metadata
/// under every one of them turned the row back into the catalogue this
/// carousel replaced. Both are still a tap away on the Schedule Card.
class _CentredCaption extends StatelessWidget {
  const _CentredCaption({required this.film});

  final Film film;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        // AnimatedSwitcher's default layout stacks the outgoing child
        // under the incoming one, which for two long titles renders them
        // superimposed — "PRADHAMA DR|PRESSURE|TTAKKAR" — for the length
        // of the transition. Dropping the previous children from layout
        // keeps the fade-in but guarantees only one title is ever drawn.
        layoutBuilder: (currentChild, previousChildren) =>
            currentChild ?? const SizedBox.shrink(),
        // Keyed on the film so the switcher actually sees a new child;
        // without this the text changes in place and never animates.
        child: Column(
          key: ValueKey(film.filmId),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              film.title,
              style: AppTypography.displayMedium,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Position indicator. The active dot stretches into a short gold bar
/// rather than just brightening — a length change is legible at this
/// size in a way a colour change alone isn't.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  /// Past this many films a row of dots stops reading as position and
  /// becomes a grey smear — twenty 4px dots tell you nothing about where
  /// you are — so nothing is drawn at all. A numeric counter sat here
  /// instead for a while; it was accurate and it was clutter, and the
  /// carousel reads fine without either, since the neighbouring posters
  /// already say there is more to the row.
  static const int _maxDots = 8;

  @override
  Widget build(BuildContext context) {
    if (count < 2 || count > _maxDots) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: 4,
            width: i == index ? 18 : 4,
            decoration: BoxDecoration(
              color: i == index ? AppColors.gold : AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}
