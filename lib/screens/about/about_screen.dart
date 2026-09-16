import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/dotted_line.dart';
import '../../widgets/section_header.dart';
import '../../widgets/vignette_backdrop.dart';

/// Proposal screen 12 — the product's one claim (a ticket's printed time
/// isn't the real start time), how the ad-block timings are sourced, and
/// the two-person team with tappable LinkedIn links. Names and links are
/// left as placeholders for you and your teammate to fill in — swap
/// [_Developer]'s two entries below for the real ones.
///
/// Static content: the timing card's 9:00 / 18 min / 9:18 numbers are
/// illustrative copy rather than pulled from a specific screening.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _developers = [
    _Developer(name: 'Abdullah Almaneea', role: 'Junior CS Student', linkedIn: 'https://www.linkedin.com/in/abdullah-maneea-299376344/'),
    _Developer(name: 'Latifa Almaneea', role: 'Senior SWE Student', linkedIn: 'https://www.linkedin.com/in/latifa-m-62b518322/'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Row(
                  children: [
                    _BackButton(onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(width: 14),
                    Text(
                      'ABOUT US',
                      style: AppTypography.display(size: 22, height: 1, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                  children: [
                    const _TimingCard(),
                    const SizedBox(height: 26),
                    Text(
                      'YOUR TICKET SAYS 9:00. THE FILM ACTUALLY STARTS AT 9:18. WE TIMED IT.',
                      style: AppTypography.display(size: 30, height: 1.02, letterSpacing: 0.4, color: AppColors.gold),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Every cinema ticket states a time that is not the time the film begins. '
                      'Ticked tells you the real start time, the real end time, and when it\'s safe '
                      'to leave your seat — using ad-block timings researched directly at each '
                      'cinema chain in Riyadh.',
                      style: AppTypography.manropeStyle(size: 14.5, height: 1.6, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'The ad block is researched by the team, not learned from users — it doesn\'t '
                      'get more accurate with use. Safe breaks are AI-generated on first request and '
                      'cached forever after, so only the first person to watch a film pays the cost.',
                      style: AppTypography.manropeStyle(size: 14.5, height: 1.6, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 30),
                    const SectionHeader(label: 'THE TEAM'),
                    const SizedBox(height: 16),
                    for (var i = 0; i < _developers.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _TeamRow(developer: _developers[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: CircleBorder(side: BorderSide(color: AppColors.gold.withValues(alpha: 0.3))),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton(
          padding: EdgeInsets.zero,
          onPressed: onPressed,
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 15, color: AppColors.gold),
        ),
      ),
    );
  }
}

/// The hero element: ticket time struck through, a dashed connector, the
/// real start time in gold — the screen's one claim rendered as a visual
/// instead of just a headline.
class _TimingCard extends StatelessWidget {
  const _TimingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TICKET SAYS',
                    style: AppTypography.manropeStyle(size: 9.5, weight: FontWeight.w600, letterSpacing: 1.4, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '9:00',
                    style: AppTypography.mono(size: 30, weight: FontWeight.w500, color: AppColors.textTertiary).copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppColors.gold.withValues(alpha: 0.6),
                      decorationThickness: 1.6,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DottedLine(color: AppColors.gold.withValues(alpha: 0.5), dashWidth: 5, dashGap: 5),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'FILM STARTS',
                    style: AppTypography.manropeStyle(size: 9.5, weight: FontWeight.w600, letterSpacing: 1.4, color: AppColors.gold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '9:18',
                    style: AppTypography.mono(size: 38, weight: FontWeight.w500, letterSpacing: -1, color: AppColors.gold),
                  ),
                ],
              ),
            ],
          ),
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.gold.withValues(alpha: 0.12))),
            ),
            child: Text(
              '18 MINUTES OF ADS · MEASURED, NOT GUESSED',
              style: AppTypography.manropeStyle(size: 10.5, weight: FontWeight.w500, letterSpacing: 0.6, color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Developer {
  const _Developer({required this.name, required this.role, required this.linkedIn});

  final String name;
  final String role;
  final String linkedIn;
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({required this.developer});

  final _Developer developer;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surface2,
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
          ),
          child: Text(
            developer.name.isNotEmpty ? developer.name[0].toUpperCase() : '?',
            style: AppTypography.display(size: 19, height: 1, color: AppColors.gold),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                developer.name,
                style: AppTypography.manropeStyle(size: 14.5, weight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 3),
              Text(
                developer.role,
                style: AppTypography.mono(size: 11, weight: FontWeight.w500, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        _LinkedInPill(url: developer.linkedIn),
      ],
    );
  }
}

/// The LinkedIn button: visually a small pill, but with its tap target
/// padded out to the 44×44 minimum so it stays comfortably tappable.
class _LinkedInPill extends StatelessWidget {
  const _LinkedInPill({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: AppColors.gold.withValues(alpha: 0.12),
        highlightColor: AppColors.gold.withValues(alpha: 0.12),
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
              ),
              child: Text(
                'LINKEDIN',
                style: AppTypography.manropeStyle(size: 10, weight: FontWeight.w600, letterSpacing: 1.2, color: AppColors.gold),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
