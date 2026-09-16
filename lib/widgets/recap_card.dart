import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_typography.dart';
import '../models/yearly_recap.dart';
import '../utils/date_format.dart';
import 'shimmer_bar.dart';
import 'stat_tile.dart';

/// The bottom band of the ticket-stub Profile card — "how much have I
/// watched" for the year: films, cinemas, time at the cinema, and the
/// ad-minutes headline. It sits directly under the card's perforation,
/// inside the same clipped stub as the identity band above it, so it only
/// owns its own background (a hint of [AppColors.velvet] fading in from
/// [AppColors.surface]) rather than a card shape of its own — that used to
/// be a separate bordered, rounded card floating below the profile header.
class RecapCard extends StatelessWidget {
  const RecapCard({super.key, required this.recap});

  /// Null while the first load is still in flight.
  final YearlyRecap? recap;

  @override
  Widget build(BuildContext context) {
    final recap = this.recap;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surface, AppColors.recapGradientEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${recap?.year ?? DateTime.now().year} RECAP',
            style: AppTypography.mono(size: 9.5, weight: FontWeight.w600, letterSpacing: 1.71, color: AppColors.gold),
          ),
          const SizedBox(height: 10),
          if (recap == null)
            const ShimmerBar(width: 230, height: 14)
          else
            Text(
              recap.totalAdMinutes == 0
                  ? 'Check in to your first screening and your recap starts here.'
                  : 'You have watched ${recap.totalAdHours.toStringAsFixed(1)} hours of advertisements this year.',
              style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w400),
            ),
          const SizedBox(height: 20),
          StatTile(value: recap == null ? null : '${recap.filmsWatched}', label: 'FILMS'),
          const SizedBox(height: 12),
          StatTile(value: recap == null ? null : '${recap.cinemasVisited}', label: 'CINEMAS'),
          const SizedBox(height: 12),
          StatTile(
            value: recap == null ? null : formatMinutes(recap.totalWatchMinutes),
            label: 'AT THE CINEMA',
            valueColor: AppColors.gold,
          ),
        ],
      ),
    );
  }
}
