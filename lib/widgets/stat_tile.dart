import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import 'dotted_line.dart';
import 'shimmer_bar.dart';

/// One line of the ticket stub's recap band: a label, a dotted leader, and
/// the number that matters — "FILMS ······ 2" — the way a paper ticket or
/// a receipt lines a name up against a price. Stacked three times inside
/// `RecapCard`, replacing the row of three boxed tiles this used to be:
/// a tile only had room for a digit or two, and "AT THE CINEMA" never fit.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.valueColor});

  final String label;

  /// Null while the recap is still loading — the label and the leader
  /// still draw, only the value itself shimmers.
  final String? value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: AppTypography.mono(size: 9.5, letterSpacing: 1.52, color: AppColors.textTertiary)),
        const SizedBox(width: 8),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: DottedLine(dashWidth: 1.6, dashGap: 3, strokeWidth: 1.6, strokeCap: StrokeCap.round),
          ),
        ),
        const SizedBox(width: 8),
        value == null
            ? const ShimmerBar(width: 30, height: 15)
            : Text(
                value!,
                style: AppTypography.mono(
                  size: 19,
                  weight: FontWeight.w700,
                  color: valueColor ?? AppColors.textPrimary,
                ),
              ),
      ],
    );
  }
}
