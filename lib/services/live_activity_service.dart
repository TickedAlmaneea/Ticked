import 'dart:io';

import 'package:flutter_app_group_directory/flutter_app_group_directory.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:live_activities/live_activities.dart';

import '../models/schedule.dart';

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
/// The on-screen countdown number itself is drawn natively by the
/// widget extension's own `Text(timerInterval:)`, which ticks on its
/// own without Dart pushing an update every second — so [onTick] below
/// only actually talks to the platform when the *phase* changes (ad
/// block ends, a break starts or ends), not on every 1-second tick of
/// the Schedule Card's own timer.
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
  Future<void> start(Schedule schedule) async {
    if (!Platform.isIOS) return;
    _phaseKey = null;
    _posterPath = await _cachePosterIfNeeded(schedule.film.posterUrl);
    try {
      final activityId = 'ticked_${DateTime.now().microsecondsSinceEpoch}';
      final state = _stateFor(schedule, 0);
      final created = await _plugin.createActivity(activityId, state);
      print('LiveActivity createActivity result: $created');
      _activityId = created != null ? activityId : null;
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

  /// Called from the Schedule Card's existing 1-second ticker. Cheap to
  /// call every second — it only pushes an update when the phase label
  /// actually changed since the last tick.
  Future<void> onTick(Schedule schedule, int elapsedMinutes) async {
    final id = _activityId;
    if (id == null || !Platform.isIOS) return;

    final state = _stateFor(schedule, elapsedMinutes);
    if (state['phase'] == _phaseKey) return;
    _phaseKey = state['phase'] as String;

    try {
      await _plugin.updateActivity(id, state);
    } catch (_) {
      // Best-effort — a failed update just means a stale phase label
      // until the next transition tries again.
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

  Map<String, dynamic> _stateFor(Schedule schedule, int elapsedMinutes) {
    final nextBreak = schedule.nextBreakAfter(elapsedMinutes);
    final trueStart = schedule.trueStartTime;
    final trueEnd = schedule.trueEndTime;

    late final String phase;
    late final String label;
    late final DateTime targetDate;

    if (elapsedMinutes < schedule.adMinutes) {
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

    return {
      'filmTitle': schedule.film.title,
      'cinemaLabel': '${schedule.branch.cinemaName} · ${schedule.branch.branchName}',
      'phase': phase,
      'label': label,
      'posterPath': _posterPath ?? '',
      'targetDate': DateTime.fromMillisecondsSinceEpoch(
  targetDate.toUtc().millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String(),
    };
  }
}
