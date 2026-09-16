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

  Film film({int? creditsStartMin, int? creditSceneStartMin}) => Film(
        filmId: 1,
        movieId: 1,
        title: 'Test Film',
        durationMin: 120,
        creditsStartMin: creditsStartMin,
        creditSceneStartMin: creditSceneStartMin,
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

  test('hasCreditScene reads the three states correctly', () {
    expect(film(creditSceneStartMin: 116).hasCreditScene, isTrue);
    expect(film(creditSceneStartMin: 120).hasCreditScene, isFalse);
    expect(film().hasCreditScene, isFalse);

    expect(film(creditSceneStartMin: 120).creditSceneChecked, isTrue);
    expect(film().creditSceneChecked, isFalse);
  });
}
