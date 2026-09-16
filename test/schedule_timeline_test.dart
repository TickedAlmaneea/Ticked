import 'package:flutter_test/flutter_test.dart';

import 'package:final_project/models/branch.dart';
import 'package:final_project/models/film.dart';
import 'package:final_project/models/schedule.dart';
import 'package:final_project/models/timeline_segment.dart';

/// Covers the credits / credits-scene split — the one place where the
/// three states of `credit_scene_start_min` turn into pixels, and where
/// getting the sentinel wrong would either hide a real scene or invent
/// one that isn't there.
void main() {
  const branch = Branch(id: 1, cinemaName: 'Reel', branchName: 'Granada Mall');

  Film film({int? creditsStartMin, int? creditSceneStartMin, int? creditSceneEndMin}) => Film(
        filmId: 1,
        movieId: 1,
        title: 'Test Film',
        durationMin: 120,
        creditsStartMin: creditsStartMin,
        creditSceneStartMin: creditSceneStartMin,
        creditSceneEndMin: creditSceneEndMin,
      );

  Schedule scheduleFor(Film f) => Schedule(
        branch: branch,
        film: f,
        ticketTime: DateTime(2026, 9, 16, 14, 0),
        adMinutes: 10,
        breaks: const [],
      );

  List<TimelineSegment> of(List<TimelineSegment> segments, TimelineSegmentKind kind) =>
      segments.where((s) => s.kind == kind).toList();

  test('a film with a credits scene draws credits AND the scene on top', () {
    final segments = scheduleFor(
      film(creditsStartMin: 112, creditSceneStartMin: 116),
    ).buildTimeline();

    final credits = of(segments, TimelineSegmentKind.credits);
    final scene = of(segments, TimelineSegmentKind.creditScene);

    expect(credits, hasLength(1));
    expect(scene, hasLength(1));

    // Offset by the 10-minute ad block.
    expect(credits.single.startMin, 122);
    expect(credits.single.endMin, 130);
    expect(scene.single.startMin, 126);
    expect(scene.single.endMin, 130);

    // The scene must come last, so SegmentedTimeline paints it over the
    // credits span it sits inside.
    expect(segments.last.kind, TimelineSegmentKind.creditScene);
  });

  test('a film with credits but no scene draws only the grey credits span', () {
    // 120 == durationMin is the "asked, no scene" sentinel.
    final segments = scheduleFor(
      film(creditsStartMin: 112, creditSceneStartMin: 120),
    ).buildTimeline();

    expect(of(segments, TimelineSegmentKind.credits), hasLength(1));
    expect(of(segments, TimelineSegmentKind.creditScene), isEmpty);
  });

  test('a film never asked about draws neither', () {
    final segments = scheduleFor(film()).buildTimeline();

    expect(of(segments, TimelineSegmentKind.credits), isEmpty);
    expect(of(segments, TimelineSegmentKind.creditScene), isEmpty);
  });

  test('the old sentinel in credits_start_min draws no credits span', () {
    // Rows written before the split stored credits_start_min == duration
    // to mean "no scene". That must not now surface as a full-width
    // credits span covering the whole film.
    final segments = scheduleFor(
      film(creditsStartMin: 120, creditSceneStartMin: null),
    ).buildTimeline();

    expect(of(segments, TimelineSegmentKind.credits), isEmpty);
  });

  test('a bounded scene leaves credits showing on both sides of it', () {
    // credits 112 -> 120, scene 114 -> 116. The grey credits span runs
    // the whole tail and the scene paints over only its own stretch, so
    // there is credits time visible before AND after it.
    final segments = scheduleFor(
      film(creditsStartMin: 112, creditSceneStartMin: 114, creditSceneEndMin: 116),
    ).buildTimeline();

    final credits = of(segments, TimelineSegmentKind.credits).single;
    final scene = of(segments, TimelineSegmentKind.creditScene).single;

    expect(credits.startMin, 122);
    expect(credits.endMin, 130);
    expect(scene.startMin, 124);
    expect(scene.endMin, 126);

    expect(scene.startMin, greaterThan(credits.startMin), reason: 'credits before the scene');
    expect(scene.endMin, lessThan(credits.endMin), reason: 'credits after the scene');
  });

  test('credits grey covers the whole credits run, red only over the scene', () {
    // Credits take the last 15 minutes (105 -> 120) with a scene at
    // 110 -> 112 inside them. The grey must span all 15 minutes; the red
    // must cover only the scene, leaving grey either side.
    final segments = scheduleFor(
      film(creditsStartMin: 105, creditSceneStartMin: 110, creditSceneEndMin: 112),
    ).buildTimeline();

    final credits = of(segments, TimelineSegmentKind.credits).single;
    final scene = of(segments, TimelineSegmentKind.creditScene).single;

    // Grey: the full 15-minute credits run (offset by the 10-min ads).
    expect(credits.startMin, 115);
    expect(credits.endMin, 130);
    expect(credits.lengthMin, 15);

    // Red: only the 2-minute scene, sitting inside the grey.
    expect(scene.startMin, 120);
    expect(scene.endMin, 122);
    expect(scene.lengthMin, 2);

    // 5 minutes of grey before the scene, 8 minutes after.
    expect(scene.startMin - credits.startMin, 5);
    expect(credits.endMin - scene.endMin, 8);
  });

  test('both minutes at the runtime means no scene, so nothing red is drawn', () {
    final segments = scheduleFor(
      film(creditsStartMin: 105, creditSceneStartMin: 120, creditSceneEndMin: 120),
    ).buildTimeline();

    expect(of(segments, TimelineSegmentKind.credits).single.lengthMin, 15);
    expect(of(segments, TimelineSegmentKind.creditScene), isEmpty);
  });

  test('a scene with no end falls back to running to the end of the film', () {
    final segments = scheduleFor(
      film(creditsStartMin: 112, creditSceneStartMin: 116),
    ).buildTimeline();

    expect(of(segments, TimelineSegmentKind.creditScene).single.endMin, 130);
  });

  test('a backwards or overlong scene end is rejected, not drawn', () {
    // End at or before the start would paint a backwards span.
    expect(film(creditSceneStartMin: 116, creditSceneEndMin: 116).creditSceneEndOr, 120);
    expect(film(creditSceneStartMin: 116, creditSceneEndMin: 110).creditSceneEndOr, 120);
    // Past the runtime would overflow the bar.
    expect(film(creditSceneStartMin: 116, creditSceneEndMin: 200).creditSceneEndOr, 120);
    // A sane window survives intact.
    expect(film(creditSceneStartMin: 114, creditSceneEndMin: 116).creditSceneEndOr, 116);
  });

  test('a scene with a start but no end is treated as not yet answered', () {
    // The half-answered state: rows written before credit_scene_end_min
    // existed. These must go back to Gemini once to learn their end.
    expect(film(creditSceneStartMin: 114, creditSceneEndMin: null).creditSceneChecked, isFalse);

    // Once the end is known, it is answered and never re-asked.
    expect(film(creditSceneStartMin: 114, creditSceneEndMin: 116).creditSceneChecked, isTrue);

    // A film with NO scene has nothing to bound — a null end is complete,
    // and it must not be dragged back to Gemini on its account.
    expect(film(creditSceneStartMin: 120, creditSceneEndMin: null).creditSceneChecked, isTrue);
  });

  test('hasCreditScene reads the three states correctly', () {
    expect(film(creditSceneStartMin: 116).hasCreditScene, isTrue);
    expect(film(creditSceneStartMin: 120).hasCreditScene, isFalse);
    expect(film().hasCreditScene, isFalse);

    expect(film(creditSceneStartMin: 120).creditSceneChecked, isTrue);
    expect(film().creditSceneChecked, isFalse);
  });
}
