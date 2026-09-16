/// What kind of span a [TimelineSegment] represents — drawn in its own
/// colour per F4 (`AppColors.timelineAds` / `timelineFilm` /
/// `timelineBreak` / `timelineCredits` / `timelineCreditScene`).
///
/// [credits] and [creditScene] are two different things and are drawn as
/// two different spans: the credits are when the film is over and you may
/// leave, the credit scene is the reason not to. A film can have the
/// first without the second — most do.
enum TimelineSegmentKind { ads, film, safeBreak, credits, creditScene }

/// One coloured span on the segmented timeline, in minutes from the
/// ticket time (minute 0 = seating begins).
class TimelineSegment {
  const TimelineSegment({required this.kind, required this.startMin, required this.endMin});

  final TimelineSegmentKind kind;
  final int startMin;
  final int endMin;

  int get lengthMin => endMin - startMin;
}
