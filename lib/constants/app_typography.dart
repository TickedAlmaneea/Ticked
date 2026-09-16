import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Interval's type system — three families, each with one job.
///
/// All three are in the Google Fonts library, so they are pulled by the
/// `google_fonts` package and need no asset declarations in `pubspec.yaml`:
///
/// * **Bebas Neue** — display. Condensed, all-caps, used for the moment that
///   matters ("LEAVE NOW") and nothing else. It has a single weight.
/// * **JetBrains Mono** — timer digits only. Tabular figures mean "42:18" does
///   not jitter as it counts down, which matters on a screen whose whole point
///   is a clock.
/// * **Manrope** — body. Clean and readable; carries the explanations, never
///   the headline moment.
abstract final class AppTypography {
  // ---------------------------------------------------------------------------
  // Display — Bebas Neue
  // ---------------------------------------------------------------------------

  /// The one big statement on a screen. All caps by design of the face itself.
  static TextStyle displayLarge = GoogleFonts.bebasNeue(
    fontSize: 44,
    height: 1.0,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
  );

  /// Screen titles and section headers.
  static TextStyle displayMedium = GoogleFonts.bebasNeue(
    fontSize: 30,
    height: 1.05,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
  );

  /// Small caps label — the eyebrow above a section.
  static TextStyle displaySmall = GoogleFonts.bebasNeue(
    fontSize: 18,
    height: 1.1,
    letterSpacing: 1.2,
    color: AppColors.textSecondary,
  );

  /// A Bebas Neue headline at an arbitrary size — the ticket-stub Profile
  /// screen's cardholder name (46) and numbered list labels (28) sit
  /// between [displayLarge] and [displayMedium] rather than matching
  /// either one, so they get this instead of a fourth named constant.
  static TextStyle display({
    required double size,
    double height = 1.0,
    double letterSpacing = 0.5,
    Color color = AppColors.textPrimary,
  }) {
    return GoogleFonts.bebasNeue(
      fontSize: size,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
  }

  // ---------------------------------------------------------------------------
  // Timer — JetBrains Mono
  // ---------------------------------------------------------------------------

  /// The countdown on Live Session. Gold, because it is the number that
  /// matters. `FontFeature.tabularFigures()` is what stops the layout shifting
  /// as digits change.
  static TextStyle timerLarge = GoogleFonts.jetBrainsMono(
    fontSize: 52,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: -1,
    color: AppColors.gold,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Inline clock values — true start, true end, elapsed.
  static TextStyle timerMedium = GoogleFonts.jetBrainsMono(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.1,
    color: AppColors.textPrimary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// Timestamps on the timeline and in history rows.
  static TextStyle timerSmall = GoogleFonts.jetBrainsMono(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: AppColors.textTertiary,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// A JetBrains Mono caption or stat value at an arbitrary size — the
  /// ticket-stub Profile screen needs several sizes this family has no
  /// named style for (its serial number, "ADMIT ONE", the recap label, the
  /// stat values). Kept here, not hard-coded in a widget, so every mono
  /// caption on that screen still comes from one place.
  static TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    Color color = AppColors.textTertiary,
    double height = 1.0,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }

  // ---------------------------------------------------------------------------
  // Body — Manrope
  // ---------------------------------------------------------------------------

  static TextStyle bodyLarge = GoogleFonts.manrope(
    fontSize: 17,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle bodyMedium = GoogleFonts.manrope(
    fontSize: 15,
    height: 1.5,
    color: AppColors.textSecondary,
  );

  static TextStyle bodySmall = GoogleFonts.manrope(
    fontSize: 13,
    height: 1.45,
    color: AppColors.textTertiary,
  );

  /// Button and field labels.
  static TextStyle label = GoogleFonts.manrope(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    letterSpacing: 0.2,
    color: AppColors.textPrimary,
  );

  /// The uppercase micro-label above a field or a stat.
  static TextStyle overline = GoogleFonts.manrope(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: 1.4,
    color: AppColors.textTertiary,
  );

  /// A Manrope caption, label or button label at an arbitrary size —
  /// mirrors [mono] and [display] for the one family that didn't yet
  /// have an escape hatch. The About Us screen's timing-card labels
  /// (9.5px) and LinkedIn pill (10px) need sizes none of the named
  /// styles above cover.
  static TextStyle manropeStyle({
    required double size,
    FontWeight weight = FontWeight.w400,
    double letterSpacing = 0,
    Color color = AppColors.textSecondary,
    double height = 1.4,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      color: color,
      height: height,
    );
  }
}
