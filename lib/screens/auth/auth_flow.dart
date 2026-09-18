import 'package:flutter/material.dart';

import '../../services/database.dart';
import '../main_shell.dart';
import 'auth_switch_route.dart';
import 'confirm_email_screen.dart';
import 'forgot_password_screen.dart';
import 'set_new_password_screen.dart';
import 'sign_in_screen.dart';
import 'sign_up_screen.dart';

/// Wires Sign In <-> Sign Up <-> Confirm Email <-> Forgot Password
/// together, backed by the real [Database].
///
/// The screens below are unchanged and know nothing about Supabase:
/// they take callbacks, and render whatever exception those throw as an
/// inline banner. [Database.readableAuthError] is what makes that work
/// — it turns Supabase's `AuthException(message: ..., statusCode: ...)`
/// into the plain sentences these screens expect.
class AuthFlow extends StatelessWidget {
  const AuthFlow({super.key});

  void _goToMainShell(BuildContext context) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final database = Database();

    return SignInScreen(
      onSignIn: (email, password) async {
        await database.signIn(email, password);
        if (context.mounted) _goToMainShell(context);
      },
      onCreateAccount: () => Navigator.of(context).push(
        AuthSwitchRoute(
          builder: (signUpContext) => SignUpScreen(
            onRegister: (name, email, password) async {
              // Confirmation is on, so signing up leaves the account
              // unconfirmed and hands back no session — the code screen
              // is the only way forward from here.
              await database.signUp(email, password, name);
              if (signUpContext.mounted) _goToConfirmEmail(signUpContext, database, email);
            },
            onSignIn: () => Navigator.of(signUpContext).pop(),
          ),
        ),
      ),
      onForgotPassword: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (forgotContext) => ForgotPasswordScreen(
            onSendReset: database.sendPasswordReset,
            onVerifyCode: (email, code) async {
              // A correct code signs the user in with a recovery session;
              // nothing but choosing a new password should be reachable.
              await database.verifyResetCode(email, code);
              if (forgotContext.mounted) _goToSetNewPassword(forgotContext, database);
            },
          ),
        ),
      ),
    );
  }

  /// Replaces the whole stack, so there is nothing behind the code
  /// screen to swipe or pop back to — an unconfirmed account has no
  /// screen it could sensibly return to.
  void _goToConfirmEmail(BuildContext context, Database database, String email) {
    final navigator = Navigator.of(context);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => ConfirmEmailScreen(
          email: email,
          onVerifyCode: (code) async {
            // A correct code confirms the address and returns a real
            // session — the first moment the app proper is reachable.
            await database.verifySignUpCode(email, code);
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            );
          },
          onResendCode: () => database.resendSignUpCode(email),
          onUseAnother: () async {
            // Nothing to sign out of in practice — confirmation-on
            // sign-up never made a session — but clear it anyway so a
            // future change to that behaviour can't leak one through.
            await database.signOut();
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthFlow()),
              (route) => false,
            );
          },
        ),
      ),
      (route) => false,
    );
  }

  void _goToSetNewPassword(BuildContext context, Database database) {
    final navigator = Navigator.of(context);
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => SetNewPasswordScreen(
          onSave: (password) async {
            await database.updatePassword(password);
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const MainShell()),
              (route) => false,
            );
          },
          onCancel: () async {
            await database.signOut();
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthFlow()),
              (route) => false,
            );
          },
        ),
      ),
      (route) => false,
    );
  }
}
