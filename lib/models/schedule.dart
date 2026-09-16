import 'branch.dart';
import 'film.dart';
import 'film_break.dart';
import 'timeline_segment.dart';

/// The computed schedule for one screening — F3. Deliberately derived,
/// device-only data: per the proposal, "the schedule shown during a
/// screening is derived data, [and] is held on the device for the life
/// of the session rather than written back." Nothing here is persisted
/// directly; [recordAttendance] only ever writes the inputs that
/// produced it.
class Schedule {
  const Schedule({
    required this.branch,
    required this.film,
    required this.ticketTime,
    required this.adMinutes,
    required this.breaks,
  });

  final Branch branch;
  final Film film;

  /// The time printed on the ticket — minute 0 of the timeline.
  final DateTime ticketTime;

  /// The researched ad block for this chain and film length.
  final int adMinutes;

  final List<FilmBreak> breaks;

  DateTime get trueStartTime => ticketTime.add(Duration(minutes: adMinutes));

  DateTime get trueEndTime => trueStartTime.add(Duration(minutes: film.durationMin));

  /// Minutes from ticket time to the very end of the screening — the
  /// full width of the segmented timeline.
  int get totalMinutes => adMinutes + film.durationMin;

  /// The ad block, the film body, any safe breaks, the credits (when
  /// known) and a credits scene (when the film has one) as coloured
  /// spans, in the order they're drawn.
  List<TimelineSegment> buildTimeline() {
    final segments = <TimelineSegment>[
      TimelineSegment(kind: TimelineSegmentKind.ads, startMin: 0, endMin: adMinutes),
      TimelineSegment(
        kind: TimelineSegmentKind.film,
        startMin: adMinutes,
        endMin: adMinutes + film.durationMin,
      ),
    ];

    for (final b in breaks) {
      segments.add(
        TimelineSegment(
          kind: TimelineSegmentKind.safeBreak,
          startMin: adMinutes + b.startMin,
          endMin: adMinutes + b.endMin,
        ),
      );
    }

    // Credits starting at the runtime means "not known" — the film is
    // treated as running to its end, and there is no credits span to
    // draw. Only a real, earlier credits minute gets a segment.
    //
    // This is drawn for every film whose credits minute is known, whether
    // or not it has a scene: on its own the grey span says "the film is
    // over here, you can go", which is worth knowing by itself.
    final creditsStart = film.creditsStartMin;
    if (creditsStart != null && creditsStart < film.durationMin) {
      segments.add(
        TimelineSegment(
          kind: TimelineSegmentKind.credits,
          startMin: adMinutes + creditsStart,
          endMin: adMinutes + film.durationMin,
        ),
      );
    }

    // ...and the scene on top of it, last, so it paints over the credits
    // span it sits inside (see SegmentedTimeline's overlay order).
    // [Film.hasCreditScene] rejects the "asked, no scene" sentinel, so
    // this only ever appears on a film that really has one.
    if (film.hasCreditScene) {
      segments.add(
        TimelineSegment(
          kind: TimelineSegmentKind.creditScene,
          startMin: adMinutes + film.creditSceneStartMin!,
          endMin: adMinutes + film.durationMin,
        ),
      );
    }

    return segments;
  }

  /// The next break at or after [elapsedMin], or null if none remain.
  FilmBreak? nextBreakAfter(int elapsedMin) {
    final filmElapsed = elapsedMin - adMinutes;
    final upcoming = breaks.where((b) => b.endMin > filmElapsed).toList()
      ..sort((a, b) => a.startMin.compareTo(b.startMin));
    return upcoming.isEmpty ? null : upcoming.first;
  }
}
