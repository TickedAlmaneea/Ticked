import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../services/database.dart';
import '../../widgets/ticked_button.dart';
import '../../widgets/vignette_backdrop.dart';
import '../auth/auth_flow.dart';

/// Proposal screen 11 — notifications, sign out, delete account.
///
/// Delete account really deletes: [Database.deleteAccount] drops the
/// `auth.users` row along with the profile and watch history, so the
/// address is free to sign up again afterwards. It needs
/// scripts/add_delete_account_function.sql to have been run on the
/// project, and says so plainly if it hasn't.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;

  Future<void> _signOut() async {
    await Database().signOut();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthFlow()),
      (route) => false,
    );
  }

  /// Signing out is one tap from a list you might be scrolling, and
  /// getting back in means the whole email-and-password round trip — so
  /// it asks first, same as Profile's own sign-out does.
  ///
  /// Separate from [_signOut] rather than folded into it, because
  /// [_confirmDeleteAccount] already has its own prompt and shouldn't
  /// ask twice.
  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Sign out?', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        content: Text(
          'You\'ll need to sign in again to get back to your tickets.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Sign out', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete account?', style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700)),
        content: Text(
          'This removes your account, your profile and your screening history. This can\'t be undone.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Database().deleteAccount();
    } catch (e) {
      // Still signed in and the account still exists — staying put with
      // the reason shown beats landing on Sign In as though it worked.
      if (!mounted) return;
      final raw = e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(raw.contains('Exception: ') ? raw.split('Exception: ').last : raw)),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthFlow()),
      (route) => false,
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
                    Text('Settings', style: AppTypography.displaySmall.copyWith(color: AppColors.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _notificationsEnabled,
                        activeColor: AppColors.gold,
                        onChanged: (v) => setState(() => _notificationsEnabled = v),
                        title: Text('Notifications', style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary)),
                        subtitle: Text('Break reminders and session alerts', style: AppTypography.bodySmall),
                      ),
                    ),
                    const SizedBox(height: 28),
                    TickedSecondaryButton(label: 'Sign out', onPressed: _confirmSignOut),
                    const SizedBox(height: 14),
                    TextButton(
                      onPressed: _confirmDeleteAccount,
                      child: Text('Delete account', style: AppTypography.label.copyWith(color: AppColors.error)),
                    ),
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
