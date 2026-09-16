import 'dart:io';

import 'package:flutter_app_group_directory/flutter_app_group_directory.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:live_activities/live_activities.dart';

import '../models/schedule.dart';
import '../utils/date_format.dart';

/// Drives the iOS Lock Screen / Dynamic Island Live Activity that mirrors
/// the Schedule Card's live countdown: "ads playing, true start in X",
/// then "next safe break in Y", then "on a break, back in Z", then
/// "movie ends in W" — so the number that matters is visible without
/// unlocking the phone.
///
/// This is a no-op everywhere except iOS 16.1+: every method checks
/// [Platform.isIOS] first and swallows failures, because a widget
/// extension that hasn't been wired up yet in Xcode (or an App Group
/// entitlement that's missing) should never be the reason the live
/// session itself breaks. Android has no equivalent API — this
/// intentionally does nothing there rather than fake one.
///
/// The on-screen countdown is a plain, Dart-formatted string, pushed
/// fresh every second while the session is live -- not iOS's own
/// `Text(timerInterval:)`, which proved unreliable in this project (the
/// countdown, and everything laid out near it, kept rendering blank on
/// device no matter how the surrounding view was structured). Once the
/// pre-show wait is over, [onTick] pushes an update every single tick of
/// the Schedule Card's own timer, not just on a phase change, since the
/// countdown text itself changes every second.
class LiveActivityService {
  LiveActivityService._();

  static final instance = LiveActivityService._();

  /// Must match the App Group configured on both the Runner and the
  /// widget extension target's "Signing & Capabilities" tab in Xcode.
  static const _appGroupId = 'group.com.example.finalProjectt.liveactivity';

  final _plugin = LiveActivities();
  String? _activityId;
  String? _phaseKey;
  String? _posterPath;

  /// Call once, early — `main()` is fine. Safe to call even before the
  /// widget extension exists; it just means Live Activities silently
  /// never appear until it does.
  Future<void> init() async {
    if (!Platform.isIOS) return;
    try {
      await _plugin.init(appGroupId: _appGroupId);
      print('LiveActivity init OK');
    } catch (e) {
      print('LiveActivity init ERROR: $e');
    }
  }

  /// Starts the Live Activity for a screening that just went live.
  ///
  /// [elapsedMinutes] is the real gap between now and [Schedule.ticketTime]
  /// (negative when Start is pressed ahead of the showtime, e.g. logging a
  /// 9pm ticket at 7pm) -- not always 0. Hard-coding 0 here would open the
  /// activity mid-way into the wrong phase whenever a ticket is logged
  /// after its ads would already have ended.
  Future<void> start(Schedule schedule, [int elapsedMinutes = 0]) async {
    if (!Platform.isIOS) return;
    _phaseKey = null;
    _posterPath = await _cachePosterIfNeeded(schedule.film.posterUrl);
    try {
      // `_plugin.createActivity`'s first argument is only a client-side
      // request label -- the value it *returns* is iOS's own real
      // activity id, generated inside ActivityKit. Every later
      // updateActivity/endActivity call has to use that real id, or the
      // native side can't find the activity ("Activity not found") and
      // silently never applies the update -- which is exactly why the
      // widget was stuck on its initial frozen text no matter what
      // onTick computed afterwards.
      final requestLabel = 'ticked_${DateTime.now().microsecondsSinceEpoch}';
      final state = _stateFor(schedule, elapsedMinutes);
      final created = await _plugin.createActivity(requestLabel, state);
      print('LiveActivity createActivity result: $created');
      _activityId = created;
      _phaseKey = state['phase'] as String;
    } catch (e) {
      print('LiveActivity start ERROR: $e');
      _activityId = null;
    }
  }

  /// Downloads the film's poster once per session and saves it inside the
  /// shared App Group container, so the widget extension can display it
  /// with a plain local file read a Live Activity has no business doing
  /// its own network fetch (tight memory budget, no guaranteed connectivity
  /// at render time). Returns null on any failure; the widget's own layout
  /// already hides the poster cleanly when this is absent.
  Future<String?> _cachePosterIfNeeded(String? posterUrl) async {
    if (posterUrl == null || posterUrl.isEmpty) return null;
    try {
      final dir = await FlutterAppGroupDirectory.getAppGroupDirectory(_appGroupId);
      if (dir == null) {
        print('LiveActivity poster cache ERROR: no App Group directory');
        return null;
      }
      final response = await http.get(Uri.parse(posterUrl));
      if (response.statusCode != 200) {
        print('LiveActivity poster download failed: HTTP ${response.statusCode}');
        return null;
      }

      // Live Activities run in a tightly memory-constrained process — a
      // full-resolution poster photo (often 1000px+ wide, several MB) is a
      // reliable way to make the widget silently fail to render. The
      // widget only ever shows this at 46x68pt, so decode once here and
      // write out a small, already-resized JPEG instead of the original.
      final decoded = img.decodeImage(response.bodyBytes);
      if (decoded == null) {
        print('LiveActivity poster decode ERROR: unrecognized image data');
        return null;
      }
      final resized = img.copyResize(decoded, width: 160);
      final smallJpg = img.encodeJpg(resized, quality: 82);

      final file = File('${dir.path}/live_activity_poster.jpg');
      await file.writeAsBytes(smallJpg);
      return file.path;
    } catch (e) {
      print('LiveActivity poster cache ERROR: $e');
      return null;
    }
  }

  /// Called from the Schedule Card's existing 1-second ticker. While
  /// still frozen in the pre-show wait, nothing needs to move so this
  /// only pushes on an actual phase change (matches the old behavior);
  /// once live, the countdown text changes every second and is pushed
  /// every tick to stay accurate.
  Future<void> onTick(Schedule schedule, int elapsedMinutes) async {
    final id = _activityId;
    if (id == null || !Platform.isIOS) return;

    final state = _stateFor(schedule, elapsedMinutes);
    final phaseChanged = state['phase'] != _phaseKey;
    if (!phaseChanged && elapsedMinutes < 0) return;
    _phaseKey = state['phase'] as String;

    try {
      await _plugin.updateActivity(id, state);
    } catch (e) {
      // Best-effort — a failed update just means a stale countdown until
      // the next tick tries again.
      print('LiveActivity updateActivity ERROR: $e');
    }
  }

  /// Ends the Live Activity. Safe to call more than once (leaving the
  /// live session, ending it normally, and disposing the screen can all
  /// reach this) — a null activity id is a no-op.
  Future<void> end() async {
    final id = _activityId;
    _activityId = null;
    _phaseKey = null;
    _posterPath = null;
    if (id == null || !Platform.isIOS) return;
    try {
      await _plugin.endActivity(id);
    } catch (_) {}
  }

  /// The evening laid out as a sequence of moments -- ads start, true
  /// start, each researched safe break, credits and a credit scene (only
  /// when the film actually has them), and finally the movie ending --
  /// for the widget's beat rail. Flat "LABEL@isoDate|LABEL@isoDate|..."
  /// text, same reasoning as the rest of this file's UserDefaults bridge:
  /// the plugin only reliably carries scalar strings across, not nested
  /// data.
  String _beatsFor(Schedule schedule) {
    final adMinutes = schedule.adMinutes;
    final breaks = schedule.breaks.toList()..sort((a, b) => a.startMin.compareTo(b.startMin));

    final entries = <MapEntry<String, int>>[
      const MapEntry('ADS', 0),
      MapEntry('TRUE START', adMinutes),
      for (var i = 0; i < breaks.length; i++)
        MapEntry(breaks.length > 1 ? 'BREAK ${i + 1}' : 'BREAK', adMinutes + breaks[i].startMin),
    ];

    final creditsStart = schedule.film.creditsStartMin;
    if (creditsStart != null && creditsStart < schedule.film.durationMin) {
      entries.add(MapEntry('CREDITS', adMinutes + creditsStart));
    }
    if (schedule.film.hasCreditScene) {
      entries.add(MapEntry('SCENE', adMinutes + schedule.film.creditSceneStartMin!));
    }
    entries.add(MapEntry('ENDS', schedule.totalMinutes));

    return entries.map((e) {
      final date = schedule.ticketTime.add(Duration(minutes: e.value));
      final iso = DateTime.fromMillisecondsSinceEpoch(
        date.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      ).toIso8601String();
      return '${e.key}@$iso';
    }).join('|');
  }

  Map<String, dynamic> _stateFor(Schedule schedule, int elapsedMinutes) {
    final nextBreak = schedule.nextBreakAfter(elapsedMinutes);
    final trueStart = schedule.trueStartTime;
    final trueEnd = schedule.trueEndTime;

    late final String phase;
    late final String label;
    late final DateTime targetDate;

    if (elapsedMinutes < 0) {
      phase = 'preShow';
      label = 'STARTS AT';
      targetDate = trueStart;
    } else if (elapsedMinutes < schedule.adMinutes) {
      phase = 'ads';
      label = 'TRUE START IN';
      targetDate = trueStart;
    } else if (nextBreak != null && elapsedMinutes < schedule.adMinutes + nextBreak.startMin) {
      phase = 'beforeBreak:${nextBreak.startMin}';
      label = 'NEXT SAFE BREAK IN';
      targetDate = trueStart.add(Duration(minutes: nextBreak.startMin));
    } else if (nextBreak != null && elapsedMinutes < schedule.adMinutes + nextBreak.endMin) {
      phase = 'duringBreak:${nextBreak.startMin}';
      label = 'SAFE BREAK ENDS IN';
      targetDate = trueStart.add(Duration(minutes: nextBreak.endMin));
    } else {
      phase = 'film';
      label = 'MOVIE ENDS IN';
      targetDate = trueEnd;
    }

    // Plain text the widget just displays as-is -- no native timer
    // machinery involved. Before the real start time, it's the frozen
    // clock time ("5:55 PM"); from then on, it's a live "H:MM:SS" (or
    // "MM:SS") count down to whatever this phase's targetDate is,
    // recomputed fresh on every push.
    final String countdownText;
    if (elapsedMinutes < 0) {
      countdownText = formatClock(schedule.ticketTime);
    } else {
      final remaining = targetDate.difference(DateTime.now());
      countdownText = formatCountdown(remaining.isNegative ? Duration.zero : remaining);
    }

    return {
      'filmTitle': schedule.film.title,
      'cinemaLabel': '${schedule.branch.cinemaName} · ${schedule.branch.branchName}',
      'phase': phase,
      'label': label,
      'posterPath': _posterPath ?? '',
      'countdownText': countdownText,
      'beats': _beatsFor(schedule),
    };
  }
}
