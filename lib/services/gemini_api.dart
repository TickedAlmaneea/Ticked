import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/film_break.dart';

/// Safe breaks couldn't be fetched — Gemini overloaded, out of quota on
/// every model, offline, or the request rejected. [message] is written
/// for a person; the Schedule Card shows a calm "not available right
/// now" with a retry either way, because the schedule itself never
/// depends on this.
class BreaksUnavailable implements Exception {
  const BreaksUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

enum GeminiFailureKind {
  /// No connection at all.
  offline,

  /// Google refused the request itself — a bad key, a bad option.
  rejected,

  /// Every model was overloaded, too slow, or out of quota.
  busy,
}

/// Why [GeminiApi.generate] got no answer. [detail] is Google's own
/// reason where it gave one, for the caller's message.
class GeminiFailure implements Exception {
  const GeminiFailure(this.kind, this.detail);

  final GeminiFailureKind kind;
  final String detail;

  @override
  String toString() => "GeminiFailure(${kind.name}): $detail";
}

/// What Gemini answered about one film: where the credits start, and the
/// windows where nothing plot-critical happens.
///
/// Lives in this file rather than in `models/` because nothing else
/// produces one — it only ever comes back from [GeminiApi].
class BreaksAnswer {
  const BreaksAnswer({
    required this.creditsStartMin,
    required this.creditSceneStartMin,
    required this.creditSceneEndMin,
    required this.breaks,
    this.isEstimate = false,
  });

  /// When the end credits begin, or null if Gemini gave nothing usable.
  final int? creditsStartMin;

  /// When the mid/post-credits scene plays. Carries the same three-state
  /// meaning [Film.creditSceneStartMin] documents — and is never null
  /// coming out of [GeminiApi.readAnswer], since having asked at all is
  /// what separates "no scene" (the sentinel) from "not asked" (null).
  final int? creditSceneStartMin;

  /// When that scene ends. Carries the same sentinel as
  /// [creditSceneStartMin]: a film with no scene has BOTH pinned to the
  /// runtime. Never null coming out of [GeminiApi.readAnswer] — null
  /// means "never asked", and a film that has been asked is answered
  /// either way.
  final int? creditSceneEndMin;

  final List<FilmBreak> breaks;

  /// True when Gemini said it reasoned from the film's runtime and
  /// likely pacing rather than knowing its scenes — see [GeminiApi.readAnswer].
  final bool isEstimate;

  /// Gemini was asked but had nothing usable for this film. The schedule
  /// is still valid, it just has no safe windows marked.
  bool get hasNoKnownBreaks => breaks.isEmpty;
}

/// The safe-break lookup — F5. Asks Gemini where a film can be safely
/// left for a few minutes, and when the credits roll.
class GeminiApi {
  /// Breaks shorter than this are useless — nobody can leave and return.
  static const int minBreakMinutes = 2;

  /// Two at most. More than that crowds the timeline, and nobody steps
  /// out of one film three times.
  static const int maxBreaks = 2;

  /// How long a mid/post-credits scene is assumed to run when Gemini
  /// says a film has one but won't say where it ends. Two minutes is the
  /// usual length of the form. Used rather than stretching the scene to
  /// the runtime, which would wrongly paint every remaining minute of
  /// credits as "stay in your seat".
  static const int typicalCreditSceneMinutes = 2;

  /// [year] is optional because nothing in the app knows it any more:
  /// `films` is scraped from a cinema's listings, which print a runtime
  /// and a poster but not a release year. The prompt simply leaves it
  /// out when it is null, and leans on the title and runtime instead.
  ///
  /// One request per film. This used to be two — a strict pass that
  /// declined on any film the model didn't know, then an estimating
  /// pass — which made the "estimated" label more trustworthy but
  /// doubled the cost of every new film against a daily quota. Now the
  /// model answers once and reports which kind of answer it gave, in
  /// the `estimated` field.
  Future<BreaksAnswer> getBreaksForFilm(
    String title,
    int durationMin, {
    int? year,
  }) async {
    final prompt = buildPrompt(title, durationMin, year: year);

    try {
      final text = await generate(prompt, thinkingLevel: "high");
      return readAnswer(text, durationMin);
    } on GeminiFailure catch (failure) {
      throw BreaksUnavailable(switch (failure.kind) {
        GeminiFailureKind.offline =>
          "No internet connection — safe breaks will load once you're back online.",
        GeminiFailureKind.rejected => "Could not load film breaks: ${failure.detail}",
        GeminiFailureKind.busy =>
          "Gemini is busy right now — safe breaks couldn't be loaded. (${failure.detail})",
      });
    }
  }

  /// One answer from Gemini as plain text, whatever it was asked —
  /// shared by the breaks lookup and the ticket reader so both absorb
  /// Google's overloads and quota limits the same way. [input] is either
  /// a prompt string or a list of content parts (text plus an image).
  ///
  /// Throws [GeminiFailure]; each caller words it for its own screen.
  Future<String> generate(Object input, {required String thinkingLevel}) async {
    String lastReason = "";

    // Models in order, each tried a couple of times. Google's servers
    // sometimes answer "currently experiencing high demand" (500/503)
    // for a few seconds at a time — nothing this app can prevent, only
    // absorb. A short retry covers a blip; switching model covers a
    // longer spike, since two different models rarely spike together,
    // and each has its own free-tier quota too.
    for (final model in models) {
      for (var attempt = 1; attempt <= attemptsPerModel; attempt++) {
        if (attempt > 1) {
          await Future.delayed(Duration(milliseconds: 1500 * (attempt - 1)));
        }

        final http.Response response;
        try {
          response = await _post(model, input, thinkingLevel).timeout(requestTimeout);
        } on TimeoutException {
          lastReason = "$model took too long to answer";
          continue; // treat like overload: retry, then fall back
        } on http.ClientException {
          // No connection. Retrying or switching model can't fix that.
          throw const GeminiFailure(GeminiFailureKind.offline, "no connection");
        }

        final status = response.statusCode;

        if (status == 200) {
          return readText(jsonDecode(response.body));
        }

        if (status == 429) {
          // This model's quota is spent. Retrying it only fails again, but
          // the next model's quota is separate — move straight on.
          lastReason = rateLimitMessage(response.body);
          break;
        }

        if (_isOverloaded(status)) {
          lastReason = "$model: ${_googleReason(response.body, status)}";
          continue;
        }

        // 400/401/403/404: the request itself is wrong (a bad key, an
        // option the model rejects). Every retry would fail the same way
        // and spend a request doing it, so stop here.
        throw GeminiFailure(GeminiFailureKind.rejected, _googleReason(response.body, status));
      }
    }

    throw GeminiFailure(GeminiFailureKind.busy, lastReason);
  }

  /// Tried in order. Flash Lite rather than Flash, for the free-tier
  /// allowance: on this project's key Gemini 3.8 Flash allows 20 requests
  /// a day, which one afternoon of testing used up, while both of these
  /// allow 500 a day and 15 a minute — counted separately, so the second
  /// is a real fallback for quota as well as for load.
  ///
  /// Check https://ai.dev/rate-limit before changing either: the limits
  /// are per model and per key, and they are what decided this.
  static const List<String> models = ["gemini-3.5-flash-lite", "gemini-3.1-flash-lite"];

  /// Two tries per model: one retry after a short wait covers a blip,
  /// and more than that mostly spends quota waiting out a real spike
  /// that the next model avoids anyway. Worst case for one film is four
  /// requests; the normal case is still one.
  static const int attemptsPerModel = 2;

  /// Thinking at "high" is slower than a plain answer, so this is
  /// generous — but a request that hangs must end in a retry or a clear
  /// message, never a spinner that never stops.
  static const Duration requestTimeout = Duration(seconds: 45);

  Future<http.Response> _post(String model, Object input, String thinkingLevel) {
    final body = {
      "model": model,
      "input": input,
      // Flash Lite has thinking OFF by default, so it was answering with
      // no reasoning step at all — quick, but overconfident: it marked a
      // templated guess for The Odyssey as known. "high" makes it reason
      // before committing. Still one request; it costs tokens (250K a
      // minute available) and seconds, not daily quota.
      "generation_config": {"thinking_level": thinkingLevel},
    };

    return http.post(
      Uri.parse("https://generativelanguage.googleapis.com/v1beta/interactions"),
      headers: {
        "x-goog-api-key": dotenv.env["GEMINI_API_KEY"]!,
        "Content-Type": "application/json",
      },
      body: jsonEncode(body),
    );
  }

  /// Google-side trouble that goes away by itself: 500 (the "high demand"
  /// message), 502/504 gateway errors, 503 unavailable.
  bool _isOverloaded(int status) =>
      status == 500 || status == 502 || status == 503 || status == 504;

  /// Google's own sentence for an error when it sent one — "(400)" alone
  /// can't tell a bad key from an option this model doesn't accept.
  String _googleReason(String body, int status) {
    try {
      final message = jsonDecode(body)["error"]?["message"]?.toString();
      if (message != null && message.isNotEmpty) return "$message ($status)";
    } catch (_) {
      // Not JSON; the status code alone will have to do.
    }
    return "HTTP $status";
  }

  /// Turns a 429 into a sentence with the actual wait in it.
  ///
  /// The free tier is limited per minute and per day, and Google's reply says
  /// exactly how long until the window reopens ("Please retry in
  /// 27.387959228s"). That number is the difference between a person
  /// waiting half a minute and assuming the feature is broken, so it is
  /// worth digging out. Falls back to a plain sentence if the body
  /// isn't shaped as expected — an unreadable error must not become a
  /// crash on top of the error.
  String rateLimitMessage(String body) {
    try {
      final message = jsonDecode(body)["error"]?["message"]?.toString() ?? "";
      final seconds = RegExp(r"retry in ([\d.]+)s").firstMatch(message)?.group(1);

      if (seconds != null) {
        final wait = double.parse(seconds).ceil();
        return "Gemini's free-tier limit has been reached. "
            "Try again in $wait seconds.";
      }
    } catch (_) {
      // Fall through to the generic message below.
    }
    return "Gemini is rate limited, try again shortly.";
  }

  /// Pulls the reply text out of Gemini's `steps` array.
  ///
  /// Found by `type`, not by index: the model puts a `"thought"` step
  /// before its answer, so the text usually sits at `steps[1]` — but
  /// nothing promises that step is always there, and `steps[1]` on a
  /// one-step reply is a range error rather than a readable failure.
  String readText(dynamic responseBody) {
    for (var step in responseBody["steps"] ?? []) {
      if (step["type"] != "model_output") continue;

      for (var part in step["content"] ?? []) {
        if (part["type"] == "text") {
          return part["text"].toString();
        }
      }
    }

    throw Exception("Gemini returned no text");
  }

  /// Asks for bare JSON so the reply can be parsed rather than read.
  String buildPrompt(String title, int durationMin, {int? year}) {
    final released = year == null ? "" : " ($year)";

    return "You are helping cinema-goers decide when they can safely step out "
        "of a screening without missing anything important.\n"
        "\n"
        "Film: \"$title\"$released, running time $durationMin minutes.\n"
        "\n"
        "Reply with ONLY a JSON object, no prose and no code fences, shaped "
        "exactly:\n"
        "\n"
        "{\"estimated\": <true or false>, \"has_credits_scene\": <true or false>, "
        "\"credits_start_min\": <integer or null>, "
        "\"credit_scene_start_min\": <integer or null>, "
        "\"credit_scene_end_min\": <integer or null>, "
        "\"breaks\": [{\"start_min\": <integer>, \"end_min\": <integer>, "
        "\"scene\": <string or null>}]}\n"
        "\n"
        "Rules:\n"
        "- All values are whole minutes from the first frame of the film, not "
        "from the advertised start time.\n"
        "- \"has_credits_scene\" is true if the film has a mid-credits or "
        "post-credits scene — something worth staying in your seat for once "
        "the credits start. If you don't know this specific film, judge from "
        "what you do know: a franchise that reliably has them (Marvel, for "
        "example) is true; a standalone drama with no such history is false.\n"
        "- \"credits_start_min\" is the minute the end credits begin. Give it "
        "for EVERY film, whether or not it has a credits scene — your best "
        "estimate is fine. It must be less than $durationMin.\n"
        "- \"credit_scene_start_min\" is the minute that extra scene actually "
        "plays. Give it only when \"has_credits_scene\" is true, otherwise set "
        "it to null. It must be greater than or equal to "
        "\"credits_start_min\" and less than $durationMin. A mid-credits "
        "scene sits shortly after the credits begin; a post-credits scene "
        "sits at the very end.\n"
        "- \"credit_scene_end_min\" is the minute that scene finishes and the "
        "ordinary credits resume. Give it only when \"has_credits_scene\" is "
        "true, otherwise null. It must be greater than "
        "\"credit_scene_start_min\" and no more than $durationMin. These "
        "scenes are short — usually one to three minutes — so do not stretch "
        "it to the end of the film unless the scene really does run into the "
        "final frame.\n"
        "- Each break is a stretch where nothing plot-critical happens: no "
        "dialogue that matters later, no reveal, no major action beat.\n"
        "- Breaks must be at least $minBreakMinutes minutes long, must not "
        "overlap, and must lie between 0 and $durationMin.\n"
        "- Return at most $maxBreaks breaks, the safest first.\n"
        "- Set \"estimated\" to false ONLY if you know this specific film's "
        "actual scenes — not its source material, not its trailer, not its "
        "genre. The test: for every break, \"scene\" must name the specific "
        "scene that ends just before the window. If you cannot name it for "
        "every break, you do not know the film: set \"estimated\" to true and "
        "\"scene\" to null. Knowing what a film is about is not the same as "
        "knowing what happens at minute 45.\n"
        "- If you do not, do NOT return an empty list. Reason from its title, "
        "runtime and likely genre, and from how films of that kind are usually "
        "paced — the lull after the first act's setup, the stretch before the "
        "climax builds — give your best windows, and set \"estimated\" to true.\n"
        "- Be honest about \"estimated\". A person may walk out during a "
        "plot twist on the strength of a window you marked as known.";
  }

  /// Turns Gemini's reply into a [BreaksAnswer], distrusting all of it.
  ///
  /// A model will eventually answer with a credits minute past the end of
  /// the film, two breaks starting on the same minute, or prose wrapped
  /// around the JSON. None of that should reach the timeline, and none of
  /// it would survive the `credits_start_min < duration_min` check or the
  /// `(film_id, start_min)` key if it were ever written to Supabase.
  BreaksAnswer readAnswer(String answer, int durationMin) {
    // Models often wrap JSON in a code fence despite being told not to,
    // so take the outermost object rather than the whole string.
    int start = answer.indexOf("{");
    int end = answer.lastIndexOf("}");

    // An unreadable reply knows nothing about the credits (null) and
    // records no scene (the durationMin sentinel) — the same outcome as
    // "asked, found nothing". It still leaves `breaks` empty, so
    // SupabaseRepository._reAskEmptyAfter brings the film back round in a
    // week rather than letting one bad reply stick permanently.
    final unreadable = BreaksAnswer(
      creditsStartMin: null,
      creditSceneStartMin: durationMin,
      creditSceneEndMin: durationMin,
      breaks: const [],
    );

    if (start == -1 || end == -1) {
      return unreadable;
    }

    dynamic jsonBody;
    try {
      jsonBody = jsonDecode(answer.substring(start, end + 1));
    } catch (e) {
      // A reply we cannot read is the same outcome as "nothing found".
      return unreadable;
    }

    // "Known" has to be claimed AND backed. The model's own
    // `estimated: false` isn't enough on its own — it said false for The
    // Odyssey with windows at 45 and 110, the same minutes it gave an
    // unrelated film it admitted guessing about. So it must also name the
    // scene beside every window; a templated guess has nothing specific
    // to name. Missing, empty or token-length scene text means estimate.
    //
    // Everything leans towards "estimate", deliberately: calling a real
    // answer a guess costs nothing, but passing a guess off as fact is
    // how someone ends up in the corridor during the twist.
    final rawBreaks = jsonBody["breaks"];
    final everyBreakNamesAScene = rawBreaks is List &&
        rawBreaks.isNotEmpty &&
        rawBreaks.every((b) {
          final scene = b is Map ? b["scene"] : null;
          return scene is String && scene.trim().length >= 12;
        });
    final isEstimate = jsonBody["estimated"] != false || !everyBreakNamesAScene;

    // The credits minute is now taken at face value for every film, and
    // means only what it says: when the credits roll. It used to be
    // overloaded to carry "has a credits scene" as well — a real minute
    // meant yes, the runtime meant no — which threw the honest credits
    // time away for every film without a scene. `credit_scene_start_min`
    // carries that answer now, so this no longer has to.
    final creditsStart = readCredits(jsonBody["credits_start_min"], durationMin);

    // Keys on `has_credits_scene`, deliberately NOT on `estimated`. An
    // earlier version treated every estimated answer as "no credits
    // scene", which wiped Spider-Man's — an unreleased film is
    // estimated, but a Marvel film still has one.
    //
    // durationMin is the "asked, no scene" sentinel (see
    // Film.creditSceneStartMin): storing it is what stops this film
    // being re-asked forever on a column that is legitimately empty.
    // When the model claims a scene but gives no usable minute for it,
    // fall back to the credits minute — "stay through the credits" is
    // still the right instruction, just less precise — and only failing
    // that give up and record no scene.
    final int creditSceneStart;
    if (jsonBody["has_credits_scene"] == true) {
      creditSceneStart =
          readCredits(jsonBody["credit_scene_start_min"], durationMin) ?? creditsStart ?? durationMin;
    } else {
      creditSceneStart = durationMin;
    }

    // Only meaningful when there actually is a scene to bound.
    //
    // When there is one, this is never left null. A null end means "not
    // answered yet" to Film.creditSceneChecked, so returning one for a
    // model that simply declined to give an end would send that film
    // back to Gemini on every single open — a quota leak on exactly the
    // films people watch most. Falling back to a typical scene length
    // both fills the column and draws the honest shape: a short scene
    // with the credits resuming after it.
    final int creditSceneEnd;
    if (creditSceneStart < durationMin) {
      final read = readSceneEnd(jsonBody["credit_scene_end_min"], creditSceneStart, durationMin);
      final assumed = creditSceneStart + typicalCreditSceneMinutes;
      creditSceneEnd = read ?? (assumed > durationMin ? durationMin : assumed);
    } else {
      // No scene: both minutes are pinned to the runtime, matching
      // creditSceneStartMin's own "asked, no scene" sentinel. Never null
      // — null means "never asked", and leaving it there would send
      // every film without a scene back to Gemini on each open.
      creditSceneEnd = durationMin;
    }

    return BreaksAnswer(
      creditsStartMin: creditsStart,
      creditSceneStartMin: creditSceneStart,
      creditSceneEndMin: creditSceneEnd,
      breaks: readBreaks(jsonBody["breaks"], durationMin, isEstimate: isEstimate),
      isEstimate: isEstimate,
    );
  }

  /// The minute a credits scene finishes. Deliberately not [readCredits]:
  /// that one rejects the runtime itself, which is right for a *start*
  /// (a scene beginning on the last frame is nonsense) but wrong here —
  /// a post-credits scene legitimately runs to the final frame.
  ///
  /// Returns null rather than a clamped guess when the model gives an end
  /// at or before the start, since a backwards span says nothing useful;
  /// the caller falls back to the end of the film.
  int? readSceneEnd(dynamic value, int startMin, int durationMin) {
    if (value is! num) {
      return null;
    }

    final minute = value.round();
    if (minute <= startMin) {
      return null;
    }
    return minute > durationMin ? durationMin : minute;
  }

  int? readCredits(dynamic value, int durationMin) {
    if (value is! num) {
      return null;
    }

    int minute = value.round();
    if (minute <= 0 || minute >= durationMin) {
      return null;
    }
    return minute;
  }

  List<FilmBreak> readBreaks(dynamic value, int durationMin, {bool isEstimate = false}) {
    if (value is! List) {
      return [];
    }

    List<FilmBreak> list = [];

    for (var item in value) {
      var rawStart = item["start_min"];
      var rawEnd = item["end_min"];

      if (rawStart is! num || rawEnd is! num) continue;

      int startMin = rawStart.round();
      int endMin = rawEnd.round();

      if (startMin < 0 || endMin > durationMin) continue;
      if (endMin - startMin < minBreakMinutes) continue;

      list.add(FilmBreak(startMin: startMin, endMin: endMin, isEstimated: isEstimate));
    }

    list.sort((a, b) => a.startMin.compareTo(b.startMin));

    // Drop any window that overlaps the one before it.
    List<FilmBreak> spaced = [];
    for (var filmBreak in list) {
      if (spaced.isNotEmpty && filmBreak.startMin < spaced.last.endMin) continue;
      spaced.add(filmBreak);
    }

    if (spaced.length > maxBreaks) {
      return spaced.sublist(0, maxBreaks);
    }
    return spaced;
  }
}
