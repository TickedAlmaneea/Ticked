import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/ticket_ocr_service.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';
import '../schedule/schedule_card_screen.dart';

/// Proposal screen 6 — a ticket photo chosen from the library or taken
/// on the spot, read by Gemini vision (see GeminiTicketOcrService). Working from
/// a still photo rather than a live camera feed removes focus, motion
/// blur and frame-selection failure entirely (Challenge 1) — you just
/// get another photo if the first one's bad.
class UploadTicketScreen extends StatefulWidget {
  const UploadTicketScreen({super.key});

  @override
  State<UploadTicketScreen> createState() => _UploadTicketScreenState();
}

class _UploadTicketScreenState extends State<UploadTicketScreen> {
  final _picker = ImagePicker();
  /// Bytes rather than a File: `dart:io` files don't exist on Flutter
  /// web, and bytes work the same on every platform.
  Uint8List? _photo;
  bool _isParsing = false;

  /// Why the last scan failed, shown over the photo until a new photo is
  /// picked or another scan starts. Null when there's nothing to say.
  String? _scanError;

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 90);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _photo = bytes;
        _scanError = null;
      });
    } catch (e) {
      if (!mounted) return;
      final isCamera = source == ImageSource.camera;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isCamera
                ? 'Couldn\'t open the camera. On the iOS Simulator there is no camera — try Library instead, or a real device.'
                : 'Couldn\'t open the photo library: $e',
          ),
        ),
      );
    }
  }

  Future<void> _useThisPhoto() async {
    final photo = _photo;
    if (photo == null) return;

    setState(() {
      _isParsing = true;
      _scanError = null;
    });
    try {
      final parsed = await appTicketOcrService.parseTicketPhoto(photo);
      if (!mounted) return;

      // Read as a ticket but nothing on it matched — an empty card
      // marked "filled in from your photo" would be misleading.
      if (parsed.isEmpty) {
        _showScanFailed('Couldn\'t read the cinema, film or time from that photo. Try a clearer one, or enter the details manually.');
        return;
      }

      // Whatever wasn't read or didn't match is left empty on the card
      // for the person to pick — see the banner there.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ScheduleCardScreen(
            preselectedFilm: parsed.film,
            preselectedCinemaName: parsed.cinemaName,
            preselectedBranchId: parsed.branch?.id,
            initialTicketTime: parsed.ticketTime,
            fromTicketPhoto: true,
            titleOnTicket: parsed.titleOnTicket,
          ),
        ),
      );
    } on TicketScanFailed catch (e) {
      if (mounted) _showScanFailed(e.message);
    } catch (e) {
      // Anything unexpected (an unreadable file, say) still ends at
      // manual entry, never a spinner or a crash.
      debugPrint('Ticket scan failed: $e');
      if (mounted) _showScanFailed('Something went wrong reading that photo.');
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  void _showScanFailed(String message) {
    setState(() => _scanError = message);
  }

  void _enterManually() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const ScheduleCardScreen()),
    );
  }

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
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                    ),
                    Text('Upload ticket', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: _photo == null
                              ? const _EmptyPhotoState()
                              : Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Image.memory(_photo!, fit: BoxFit.cover),
                                    ),
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 220),
                                      child: _isParsing
                                          ? const _ParsingOverlay()
                                          : _scanError != null
                                              ? _ScanFailedOverlay(message: _scanError!)
                                              : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: TickedSecondaryButton(
                              label: 'Library',
                              icon: Icons.photo_library_outlined,
                              onPressed: _isParsing ? null : () => _pick(ImageSource.gallery),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TickedSecondaryButton(
                              label: 'Camera',
                              icon: Icons.camera_alt_outlined,
                              onPressed: _isParsing ? null : () => _pick(ImageSource.camera),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      // After a failed scan, manual entry becomes the main
                      // action and retrying the same photo drops to the link.
                      if (_scanError == null) ...[
                        TickedPrimaryButton(
                          label: 'Use this photo',
                          isLoading: _isParsing,
                          onPressed: _photo == null ? null : _useThisPhoto,
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton(
                            onPressed: _isParsing ? null : _enterManually,
                            child: Text(
                              'Enter details manually instead',
                              style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ] else ...[
                        TickedPrimaryButton(
                          label: 'Enter details manually',
                          onPressed: _enterManually,
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: TextButton(
                            onPressed: _useThisPhoto,
                            child: Text(
                              'Try this photo again',
                              style: AppTypography.label.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPhotoState extends StatelessWidget {
  const _EmptyPhotoState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.confirmation_number_outlined, color: AppColors.textTertiary, size: 40),
        const SizedBox(height: 12),
        Text('No photo yet', style: AppTypography.bodyMedium),
      ],
    );
  }
}

class _ParsingOverlay extends StatelessWidget {
  const _ParsingOverlay();

  @override
  Widget build(BuildContext context) {
    // A pool of shade under the spinner rather than a tint over the whole
    // photo: darkest at the centre, gone by the edges, so the ticket stays
    // readable while the label still has something to sit on.
    //
    // SizedBox.expand because AnimatedSwitcher hands its child loose
    // constraints — a bare DecoratedBox would shrink to the text's width
    // and print the gradient as a band down the middle of the photo.
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 0.6,
            colors: [
              AppColors.bg.withValues(alpha: 0.78),
              AppColors.bg.withValues(alpha: 0.45),
              AppColors.bg.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.gold, strokeWidth: 2.6),
            const SizedBox(height: 14),
            Text(
              'Reading your ticket…',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                // Keeps the label legible where the gradient has already
                // faded out over a bright ticket.
                shadows: const [Shadow(color: Colors.black, blurRadius: 10)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sits over the photo when a scan fails, so the reason reads in place —
/// on the photo it's about — instead of a stock snackbar covering the
/// buttons.
class _ScanFailedOverlay extends StatelessWidget {
  const _ScanFailedOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        color: AppColors.bg.withOpacity(0.72),
        alignment: Alignment.bottomCenter,
        padding: const EdgeInsets.all(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: AppColors.errorSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.error.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 20, color: AppColors.error),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Couldn\'t read this photo',
                      style: AppTypography.label.copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick another photo from Library or Camera below.',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
