import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/timeline_segment.dart';

/// F4 — the segmented timeline: ad block, film, safe breaks, credits
/// and a credits scene as distinct coloured spans. Ads and film exactly
/// tile the full width (0..adMinutes, adMinutes..total), so they're
/// drawn as a simple two-flex base row; everything else is drawn *on
/// top* of that base at its fractional position, matching the order
/// [Schedule.buildTimeline] documents ("in the order they're drawn").
/// An optional playhead marks elapsed time during a live session.
///
/// Note: this deliberately avoids `num.clamp()` — it returns `num`,
/// not `int`/`double`, which is a classic silent-looking type trap
/// against a `double`-typed field like [Positioned.left]. Bounds below
/// are written out by hand instead.
class SegmentedTimeline extends StatelessWidget {
  const SegmentedTimeline({
    super.key,
    required this.segments,
    required this.totalMinutes,
    this.elapsedMin,
    this.height = 14,
  });

  final List<TimelineSegment> segments;
  final int totalMinutes;
  final int? elapsedMin;
  final double height;

  Color _colorFor(TimelineSegmentKind kind) {
    switch (kind) {
      case TimelineSegmentKind.ads:
        return AppColors.timelineAds;
      case TimelineSegmentKind.film:
        return AppColors.timelineFilm;
      case TimelineSegmentKind.safeBreak:
        return AppColors.timelineBreak;
      case TimelineSegmentKind.credits:
        return AppColors.timelineCredits;
      case TimelineSegmentKind.creditScene:
        return AppColors.timelineCreditScene;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (totalMinutes <= 0) {
      return SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(height / 2)),
        ),
      );
    }

    final base = segments
        .where((s) => s.kind == TimelineSegmentKind.ads || s.kind == TimelineSegmentKind.film)
        .toList();
    // Everything that isn't part of the tiling base is an overlay, kept
    // in the order Schedule.buildTimeline emitted it — which is what puts
    // a credits scene on top of the credits span it sits inside, rather
    // than under it.
    final overlays = segments
        .where((s) => s.kind != TimelineSegmentKind.ads && s.kind != TimelineSegmentKind.film)
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            double xFor(int min) {
              final ratio = min / totalMinutes;
              final bounded = ratio < 0.0 ? 0.0 : (ratio > 1.0 ? 1.0 : ratio);
              return bounded * width;
            }

            double widthFor(int startMin, int endMin) {
              final w = xFor(endMin) - xFor(startMin);
              return w < 1.0 ? 1.0 : w;
            }

            // Both `fit: expand` and `stretch` are load-bearing. The base
            // spans are empty ColoredBoxes, which have no height of their
            // own: without these, a Row hands them loose vertical
            // constraints and they collapse to 0px — the ad block and the
            // film silently vanish and only the positioned breaks show.
            return Stack(
              fit: StackFit.expand,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final s in base)
                      Expanded(
                        flex: s.lengthMin > 0 ? s.lengthMin : 1,
                        child: ColoredBox(color: _colorFor(s.kind)),
                      ),
                  ],
                ),
                for (final s in overlays)
                  Positioned(
                    left: xFor(s.startMin),
                    width: widthFor(s.startMin, s.endMin),
                    top: 0,
                    bottom: 0,
                    child: ColoredBox(color: _colorFor(s.kind)),
                  ),
                if (elapsedMin != null)
                  Positioned(
                    left: _playheadLeft(elapsedMin!, width, xFor),
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: AppColors.timelinePlayhead),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _playheadLeft(int elapsed, double width, double Function(int) xFor) {
    final e = elapsed < 0 ? 0 : (elapsed > totalMinutes ? totalMinutes : elapsed);
    final x = xFor(e) - 1;
    final maxLeft = width - 2;
    if (maxLeft < 0) return 0;
    return x < 0.0 ? 0.0 : (x > maxLeft ? maxLeft : x);
  }
}
