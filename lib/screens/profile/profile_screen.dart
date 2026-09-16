import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../data/app_repository.dart';
import '../../models/app_user.dart';
import '../../models/yearly_recap.dart';
import '../../services/database.dart';
import '../../widgets/dotted_line.dart';
import '../../widgets/recap_card.dart';
import '../../widgets/shimmer_bar.dart';
import '../../widgets/vignette_backdrop.dart';
import '../about/about_screen.dart';
import '../auth/auth_flow.dart';
import '../history/history_screen.dart';
import '../settings/settings_screen.dart';

/// Proposal screen 10, "ticket stub" direction — Profile as a torn cinema
/// ticket: a surface-coloured stub card holding the avatar, name and email,
/// split by a perforation from the yearly recap, then a numbered editorial
/// list down to Sign Out. Recreated from an external high-fidelity design
/// handoff (a Claude Design canvas package) rather than iterated on in
/// place — two earlier passes at "make it feel less flat" only ever
/// nudged spacing and colour within the previous grouped-menu layout, and
/// the person asking for this wanted a genuinely different structure, not
/// a better version of the same one.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

enum _EditAction { photo, name }

class _ProfileScreenState extends State<ProfileScreen> {
  final _picker = ImagePicker();

  AppUser? _user;
  YearlyRecap? _recap;

  /// Shown the instant a photo is picked, before the upload finishes — so
  /// tapping the avatar feels immediate rather than waiting on a round trip
  /// before anything changes on screen. Cleared once [_user]'s own
  /// `avatarUrl` reflects the upload (or the upload fails and this is
  /// dropped back to whatever was there before).
  File? _pendingAvatarFile;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The recap comes from the repository (in memory today) and is shown as
  /// soon as it resolves. The signed-in profile is a separate Supabase
  /// round trip that can hang or fail — it used to be awaited first, which
  /// left the whole page on a spinner for as long as that call took. It now
  /// loads after, and its failure costs only the card's identity band,
  /// which falls back to its shimmer state.
  Future<void> _load() async {
    final recap = await appRepository.recap(DateTime.now().year);
    if (!mounted) return;
    setState(() => _recap = recap);

    try {
      final user = await Database().getCurrentUser();
      if (!mounted) return;
      setState(() => _user = user);
    } catch (_) {
      // Not signed in, offline, or Supabase is unreachable. The recap
      // above is already on screen; the identity band keeps shimmering.
    }
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _user?.displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Display name', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppTypography.bodyLarge,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && _user != null) {
      setState(() => _user = _user!.copyWith(displayName: result));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    }
  }

  Future<void> _editAvatar() async {
    final user = _user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in again before changing your photo.')),
      );
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
              title: Text('Take photo', style: AppTypography.bodyLarge),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: Text('Choose from library', style: AppTypography.bodyLarge),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, maxWidth: 1000, imageQuality: 85);
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
      return;
    }
    if (picked == null || !mounted) return;

    final file = File(picked.path);
    setState(() {
      _pendingAvatarFile = file;
      _uploadingAvatar = true;
    });

    try {
      final avatarUrl = await Database().uploadAvatar(user.id, file);
      await Database().updateProfile(user.id, _user?.displayName ?? user.displayName, avatarUrl);
      if (!mounted) return;
      setState(() {
        _user = _user?.copyWith(avatarUrl: avatarUrl);
        _pendingAvatarFile = null;
        _uploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingAvatarFile = null;
        _uploadingAvatar = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Couldn\'t save your photo: $e')),
      );
    }
  }

  /// EDIT PROFILE opens onto the same two things the old page split
  /// across a photo tap and a pencil icon — a photo picker and a name
  /// dialog — so the design's single button still reaches both.
  Future<void> _openEditSheet() async {
    final action = await showModalBottomSheet<_EditAction>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
              title: Text('Change photo', style: AppTypography.bodyLarge),
              onTap: () => Navigator.pop(context, _EditAction.photo),
            ),
            ListTile(
              leading: const Icon(Icons.badge_outlined, color: AppColors.textPrimary),
              title: Text('Edit name', style: AppTypography.bodyLarge),
              onTap: () => Navigator.pop(context, _EditAction.name),
            ),
          ],
        ),
      ),
    );
    if (action == _EditAction.photo) await _editAvatar();
    if (action == _EditAction.name) await _editDisplayName();
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Sign out?', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign out', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await Database().signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthFlow()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        showVelvet: false,
        child: SafeArea(
          child: RefreshIndicator(
            color: AppColors.gold,
            backgroundColor: AppColors.surface,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 40),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'ADMIT ONE',
                        style: AppTypography.mono(size: 10, weight: FontWeight.w500, letterSpacing: 2.2),
                      ),
                      Text(
                        'No ${_memberNumber(user?.id)}',
                        style: AppTypography.mono(
                          size: 10,
                          weight: FontWeight.w500,
                          letterSpacing: 1.4,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Semantics(
                                  button: true,
                                  label: 'Change profile photo',
                                  child: _Pressable(
                                    onTap: _uploadingAvatar ? null : _editAvatar,
                                    child: SizedBox(
                                      width: 96,
                                      height: 96,
                                      child: Stack(
                                        children: [
                                          ClipOval(
                                            child: SizedBox.expand(
                                              child: _AvatarImage(user: user, pendingFile: _pendingAvatarFile),
                                            ),
                                          ),
                                          if (_uploadingAvatar)
                                            Positioned.fill(
                                              child: ClipOval(
                                                child: ColoredBox(
                                                  color: Colors.black45,
                                                  child: Center(
                                                    child: SizedBox(
                                                      width: 20,
                                                      height: 20,
                                                      child: CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: AppColors.gold,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: user == null
                                          ? const [
                                              ShimmerBar(width: 76, height: 9),
                                              SizedBox(height: 10),
                                              ShimmerBar(width: 130, height: 38),
                                              SizedBox(height: 11),
                                              ShimmerBar(width: 100, height: 11),
                                              SizedBox(height: 14),
                                              ShimmerBar(width: 96, height: 28, radius: 3),
                                            ]
                                          : [
                                              Text(
                                                'CARDHOLDER',
                                                style: AppTypography.mono(size: 9, letterSpacing: 1.62),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                user.displayName.isEmpty ? '—' : user.displayName.toUpperCase(),
                                                style: AppTypography.display(size: 46, height: 0.88, letterSpacing: 0.92),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 9),
                                              Text(
                                                user.email,
                                                style: AppTypography.mono(size: 11),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 14),
                                              _EditProfileButton(onTap: _openEditSheet),
                                            ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const _Perforation(),
                          RecapCard(recap: _recap),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    children: [
                      _StubListRow(
                        index: '01',
                        label: 'HISTORY',
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen())),
                      ),
                      _StubListRow(
                        index: '02',
                        label: 'SETTINGS',
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
                      ),
                      _StubListRow(
                        index: '03',
                        label: 'ABOUT US',
                        onTap: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                      ),
                      const SizedBox(height: 18),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _SignOutRow(onTap: _confirmSignOut),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A stable-looking 4-digit "membership number" derived from the account
/// id — not a real serial, just something that reads as one and does not
/// change between app launches for the same person. `String.hashCode` is
/// documented as unspecified across VM runs, so this walks the id's own
/// characters instead of trusting that.
String _memberNumber(String? id) {
  if (id == null || id.isEmpty) return '0000';
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return (hash % 10000).toString().padLeft(4, '0');
}

/// The cut between the identity band and the recap band: two `bg`-coloured
/// circles bleeding half off the stub card's edges (clipped away by the
/// card's own `ClipRRect`) with a dashed rule strung between them — a
/// paper ticket's tear line, not a divider.
class _Perforation extends StatelessWidget {
  const _Perforation();

  static const double _circle = 16;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _circle,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _circle / 2),
            child: DottedLine(dashWidth: 5, dashGap: 6, strokeWidth: 1.2),
          ),
          const Positioned(
            left: -_circle / 2,
            child: _PerfCircle(),
          ),
          const Positioned(
            right: -_circle / 2,
            child: _PerfCircle(),
          ),
        ],
      ),
    );
  }
}

class _PerfCircle extends StatelessWidget {
  const _PerfCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _Perforation._circle,
      height: _Perforation._circle,
      decoration: const BoxDecoration(color: AppColors.bg, shape: BoxShape.circle),
    );
  }
}

/// The bordered "EDIT PROFILE" pill — inverts to a filled gold chip while
/// held, the same way [TickedPrimaryButton] darkens instead of rippling
/// (the theme turns Material's ripple off everywhere on purpose).
class _EditProfileButton extends StatefulWidget {
  const _EditProfileButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_EditProfileButton> createState() => _EditProfileButtonState();
}

class _EditProfileButtonState extends State<_EditProfileButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _pressed ? AppColors.gold : Colors.transparent,
          border: Border.all(color: AppColors.goldDim),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          'EDIT PROFILE',
          style: AppTypography.mono(
            size: 9,
            weight: FontWeight.w500,
            letterSpacing: 1.44,
            color: _pressed ? AppColors.bg : AppColors.gold,
          ),
        ),
      ),
    );
  }
}

/// One row of the numbered list below the stub — "01 HISTORY →". Shifts
/// 8px to the right while held or hovered, per the handoff's own note that
/// this should be `InkWell` plus an `AnimatedPadding` rather than a ripple.
class _StubListRow extends StatefulWidget {
  const _StubListRow({required this.index, required this.label, required this.onTap});

  final String index;
  final String label;
  final VoidCallback onTap;

  @override
  State<_StubListRow> createState() => _StubListRowState();
}

class _StubListRowState extends State<_StubListRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        onTap: widget.onTap,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(left: _pressed ? 8 : 0),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 17, horizontal: 2),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hairline))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(widget.index, style: AppTypography.mono(size: 10)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.label, style: AppTypography.display(size: 28, height: 1.0, letterSpacing: 0.84)),
                ),
                Text('→', style: AppTypography.bodySmall.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "SIGN OUT →" in [AppColors.error] — the one place on this screen that
/// isn't gold-or-neutral, because a destructive action deserves its own
/// colour rather than blending into the rest of the mono captions. Dims
/// slightly while held, mirroring the handoff's hover state without
/// needing a whole button widget for it.
class _SignOutRow extends StatefulWidget {
  const _SignOutRow({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SignOutRow> createState() => _SignOutRowState();
}

class _SignOutRowState extends State<_SignOutRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: AppTypography.mono(
            size: 10,
            weight: FontWeight.w500,
            letterSpacing: 1.8,
            color: _pressed ? AppColors.error.withValues(alpha: 0.7) : AppColors.error,
          ),
          child: const Text('SIGN OUT →'),
        ),
      ),
    );
  }
}

/// The avatar's contents: a picked-but-not-yet-uploaded local file first,
/// then the saved `avatarUrl`, then the display name's initial as a last
/// resort — the same fallback ladder either way, so a slow or broken image
/// never leaves the frame blank.
class _AvatarImage extends StatelessWidget {
  const _AvatarImage({required this.user, required this.pendingFile});

  final AppUser? user;
  final File? pendingFile;

  Widget _initial() {
    return ColoredBox(
      color: AppColors.surface2,
      child: Center(
        child: Text(
          (user?.displayName.isNotEmpty ?? false) ? user!.displayName[0].toUpperCase() : '?',
          style: AppTypography.displayMedium,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingFile = this.pendingFile;
    if (pendingFile != null) {
      return Image.file(pendingFile, fit: BoxFit.cover);
    }

    final avatarUrl = user?.avatarUrl;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Image.network(
        avatarUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initial(),
        loadingBuilder: (context, child, progress) => progress == null ? child : _initial(),
      );
    }

    return _initial();
  }
}

/// The app's one press-feedback language, used here for the avatar: a
/// small scale-down while held, same 120ms feel as [TickedPrimaryButton]'s
/// colour shift. The theme turns Material's ripple off everywhere
/// (`NoSplash.splashFactory` in `AppTheme`) on purpose, so a plain
/// `GestureDetector` with no animation of its own would read as broken
/// rather than restrained.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
