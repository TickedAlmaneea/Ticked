import 'package:flutter/material.dart';

/// Interval's colour system — warm cinema direction.
///
/// One accent. A dark room. A lit screen.
///
/// The palette was authored in OKLCH and converted to sRGB; the source
/// value is kept in the comment beside each colour so a shade can be
/// re-derived rather than nudged by eye. Every hue sits between 25 and 80
/// degrees, which is what keeps the greys warm instead of blue.
///
/// The rule that matters: [gold] appears in roughly three places per screen —
/// the number that matters, the one button to press, a thin highlight border.
/// Everywhere else is [bg], [surface] and [textPrimary] doing the work. That is
/// what keeps the app feeling like a theater and not a dashboard.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Surfaces — the dark room
  // ---------------------------------------------------------------------------

  /// oklch(11% .012 50) — the app background. The darkest thing on screen.
  static const Color bg = Color(0xFF070402);

  /// oklch(17% .016 50) — cards, sheets, the Schedule Card itself.
  static const Color surface = Color(0xFF150D09);

  /// oklch(22% .018 50) — raised surfaces, input fields, the film span of the
  /// timeline. One step up from [surface], never two.
  static const Color surface2 = Color(0xFF221813);

  /// oklch(28% .016 50) — hairline dividers and unfilled track backgrounds.
  static const Color divider = Color(0xFF302722);

  /// rgba(255,255,255,.07) — a hairline drawn on top of a photograph or a
  /// gradient, where [divider] (an opaque warm grey) would read as a hard
  /// seam instead of a soft one. The ticket-stub Profile screen's list rows
  /// use this; card-on-[bg] dividers elsewhere keep using [divider].
  static const Color hairline = Color(0x12FFFFFF);

  /// oklch(25% .075 25) — atmosphere only, never UI.
  ///
  /// Deep cinema-curtain red. Use it for a full-bleed gradient wash behind the
  /// Splash or the recap card. Never as a surface a control sits on, never as
  /// text, never as a border — it does not meet contrast against anything and
  /// it is not meant to.
  static const Color velvet = Color(0xFF3E0F0E);

  /// oklch(19% .035 35) — the far end of the recap band's gradient on the
  /// ticket-stub Profile screen: [surface] fading toward this, a hint of
  /// [velvet] as atmosphere behind the year's numbers. Never a flat fill on
  /// its own.
  static const Color recapGradientEnd = Color(0xFF2A1A17);

  // ---------------------------------------------------------------------------
  // Accent — the lit screen
  // ---------------------------------------------------------------------------

  /// oklch(80% .13 75) — the one accent. 10.76:1 on [bg].
  ///
  /// The true start time, the running timer, the primary button, the ad block
  /// on the timeline. If a screen has a fourth gold element, one of them is
  /// wrong.
  static const Color gold = Color(0xFFEEB154);

  /// oklch(72% .125 73) — [gold] while a control is held down.
  static const Color goldPressed = Color(0xFFD49740);

  /// oklch(62% .10 70) — borders, dimmed gold, the safe-break spans. 5.53:1 on
  /// [bg], so it is still legible as text where a caption needs warmth.
  static const Color goldDim = Color(0xFFAD7B3D);

  /// oklch(18% .02 60) — foreground on top of a [gold] fill. 9.05:1 on [gold].
  ///
  /// Never use [bg] here: pure-dark on gold reads as a hole punched in the
  /// button rather than as a label.
  static const Color onGold = Color(0xFF211A12);

  // ---------------------------------------------------------------------------
  // Text — warm off-white, three weights of emphasis
  // ---------------------------------------------------------------------------

  /// oklch(95% .012 80) — warm off-white. Headlines and body. 17.70:1 on [bg].
  static const Color textPrimary = Color(0xFFF3EEE6);

  /// oklch(80% .012 70) — secondary copy, labels. 10.98:1 on [bg].
  static const Color textSecondary = Color(0xFFC3BDB6);

  /// oklch(65% .012 60) — captions, timestamps, the "9:17" on a ticket stub.
  /// 6.33:1 on [bg] — passes AA, and is the dimmest text the system allows.
  static const Color textTertiary = Color(0xFF958E88);

  /// Text on a surface that is disabled. Decorative only — never the sole
  /// carrier of meaning, because it does not meet contrast.
  static const Color textDisabled = Color(0xFF6B645E);

  // ---------------------------------------------------------------------------
  // Timeline segments
  // ---------------------------------------------------------------------------
  //
  // The segmented timeline (F4) draws five spans: ad block, film, safe breaks,
  // credits, and a credits scene. Every one has to read against the dark card
  // behind it AND
  // against the span next to it — the first version separated them by value
  // alone (film was surface2, credits was divider), and on a #150D09 card
  // those were effectively invisible.
  //
  // So: gold for the ads, because they are what the project measured; a warm
  // mid-grey for the film, clearly visible but quiet; a soft sage green for
  // the breaks, the one extra hue, because "safe to step out" is the thing a
  // person is scanning for; a lighter grey for credits so it separates
  // from the film it sits on the end of; and a terracotta for a credits
  // scene, the second extra hue, sitting on top of that grey.

  /// The advertising block — the measured span, drawn in the accent.
  static const Color timelineAds = gold;

  /// The film itself — the long span. Visible, but never louder than ads.
  static const Color timelineFilm = Color(0xFF5A4D44);

  /// A safe break — sage green, the only non-gold hue on the timeline, so
  /// the windows jump out of the film they sit inside.
  static const Color timelineBreak = Color(0xFF7FB77E);

  /// Closing credits — lighter than the film so the end of the film reads.
  /// Only drawn when a real credits minute is known. Deliberately quiet:
  /// this span means "the film is over, you can go", so it must never
  /// compete with [timelineCreditScene] sitting on top of it.
  static const Color timelineCredits = Color(0xFFA2958B);

  /// A mid/post-credits scene — the one span that means "do NOT leave".
  /// Terracotta, chosen as the opposite pole to [timelineBreak]'s sage:
  /// the two hues that aren't gold now read as the two opposite
  /// instructions (green "safe to step out", red-orange "stay in your
  /// seat"), which is the distinction someone is scanning the bar for.
  /// Warm enough to belong beside the gold rather than alarm against it.
  static const Color timelineCreditScene = Color(0xFFE07A5F);

  /// The playhead marking the current minute during a live session.
  static const Color timelinePlayhead = textPrimary;

  /// oklch(40% .02 60) — perforation dashes and dotted leaders on the
  /// ticket-stub Profile screen. Same shade as [timelineFilm]; kept as its
  /// own name because the two mean different things — a cut line and a
  /// leader rule, not a span of film.
  static const Color dash = Color(0xFF5A4D44);

  // ---------------------------------------------------------------------------
  // Status
  // ---------------------------------------------------------------------------

  /// oklch(63% .17 27) — validation failures, wrong credentials, network
  /// errors. 5.40:1 on [bg]. Warm enough to belong to this palette; distinct
  /// enough from [gold] that the two never read as the same signal.
  static const Color error = Color(0xFFDD574E);

  /// A tinted background for an inline error row.
  static const Color errorSurface = Color(0xFF2A100E);

  /// Skeleton and shimmer base while breaks are being generated.
  static const Color skeleton = Color(0xFF1B120D);
}
