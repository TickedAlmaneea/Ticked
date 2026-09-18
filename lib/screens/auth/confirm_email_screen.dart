import 'dart:async';

import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_typography.dart';
import '../../widgets/auth_error_banner.dart';
import '../../widgets/auth_hero.dart';
import '../../widgets/code_input.dart';
import '../../widgets/vignette_backdrop.dart';

/// The step between signing up and getting in: the account exists but
/// the address is unconfirmed, and only the code Supabase emailed will
/// confirm it.
///
/// This is the code half of `ForgotPasswordScreen` with the email step
/// dropped — sign-up already collected the address, so it is passed in
/// rather than asked for again.
///
/// There is deliberately no back button. Going back would leave an
/// unconfirmed account behind with nothing pointing at it; [onUseAnother]
/// is the way out, and AuthFlow signs the half-made session out before
/// returning to Sign In.
class ConfirmEmailScreen extends StatefulWidget {
  const ConfirmEmailScreen({
    super.key,
    required this.email,
    required this.onVerifyCode,
    required this.onResendCode,
    required this.onUseAnother,
  });

  /// The address sign-up registered — shown so a typo is obvious before
  /// the person starts waiting on an email that went elsewhere.
  final String email;

  final Future<void> Function(String code) onVerifyCode;
  final Future<void> Function() onResendCode;
  final VoidCallback onUseAnother;

  /// Must match Authentication → Providers → Email → "Email OTP Length"
  /// in the Supabase dashboard.
  static const codeLength = 6;

  /// Must not exceed SMTP Settings → "Minimum interval per user", or the
  /// resend link comes back alive while Supabase is still refusing.
  static const resendCooldown = Duration(seconds: 60);

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  final _codeController = TextEditingController();

  String? _formError;
  bool _isLoading = false;
  int _shakeCount = 0;

  Timer? _cooldownTimer;
  int _cooldownLeft = 0;

  @override
  void initState() {
    super.initState();
    // Sign-up already sent the first code, so the clock starts spent.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownLeft = ConfirmEmailScreen.resendCooldown.inSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _cooldownLeft--);
      if (_cooldownLeft <= 0) timer.cancel();
    });
  }

  Future<void> _verify(String code) async {
    if (_isLoading) return;
    setState(() {
      _formError = null;
      _isLoading = true;
    });
    try {
      await widget.onVerifyCode(code);
    } catch (e) {
      if (!mounted) return;
      _codeController.clear();
      // Re-enable in the same rebuild as the shake, so the input can take
      // focus back for the next attempt.
      setState(() {
        _isLoading = false;
        _formError = _messageFor(e);
        _shakeCount++;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _formError = null;
      _isLoading = true;
    });
    try {
      await widget.onResendCode();
      if (!mounted) return;
      _codeController.clear();
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _formError = _messageFor(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('Exception: ')) return raw.split('Exception: ').last;
    return 'Something went wrong. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: VignetteBackdrop(
        child: Column(
          children: [
            // Not part of the Sign In <-> Sign Up flight; this screen
            // just shares the look.
            const HeroMode(
              enabled: false,
              child: AuthHero(headline: ['CONFIRM YOUR', 'EMAIL.']),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 28),
                      Text.rich(
                        TextSpan(
                          text: 'Your account is ready. Enter the '
                              '${ConfirmEmailScreen.codeLength}-digit code we sent to\n',
                          children: [
                            TextSpan(
                              text: widget.email,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        style: AppTypography.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 26),
                      AuthErrorBanner(message: _formError),
                      CodeInput(
                        controller: _codeController,
                        length: ConfirmEmailScreen.codeLength,
                        enabled: !_isLoading,
                        hasError: _formError != null && _codeController.text.isEmpty,
                        shakeCount: _shakeCount,
                        onCompleted: _verify,
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 24,
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.gold,
                                  ),
                                )
                              : Text(
                                  "Can't find it? Check your spam folder.",
                                  style: AppTypography.bodySmall,
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _textLink(
                        _cooldownLeft > 0 ? 'Resend code in ${_cooldownLeft}s' : 'Resend code',
                        onPressed: _isLoading || _cooldownLeft > 0 ? null : _resend,
                      ),
                      _textLink(
                        'Use a different email',
                        onPressed: _isLoading ? null : widget.onUseAnother,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textLink(String label, {required VoidCallback? onPressed, Color color = AppColors.gold}) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        child: Text(
          label,
          style: AppTypography.label.copyWith(color: onPressed == null ? AppColors.textDisabled : color),
        ),
      ),
    );
  }
}
