import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';

/// A section eyebrow with a hairline running out to the right margin —
/// the divider is what stops a bare overline label floating unanchored
/// on a very dark background, and it reads as a strip of film leader.
///
/// [trailing] is for a count or an action sitting at the end of the rule.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: AppTypography.overline),
        const SizedBox(width: 12),
        // Takes the slack so the rule always reaches the trailing widget
        // (or the margin), whatever the label's length or text scale.
        const Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.divider)),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}
