import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../theme/rover_theme.dart';
import '../widgets/auth_dialog.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleSendLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      showErrorDialog(context, 'Please enter a valid email address.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Fix M-11: Uri.base.origin is meaningless on mobile (evaluates to
      // an empty string or 'null'). On native platforms, Supabase sends the
      // reset email using the Redirect URL configured in the Supabase
      // Dashboard (Authentication → URL Configuration → Redirect URLs).
      // We omit redirectTo here so that Supabase always uses its configured
      // value, which works correctly for both web and mobile deep links.
      //
      // To enable mobile deep links for password reset:
      //   Dashboard → Redirect URLs → add your scheme, e.g.:
      //     io.rover.app://reset-password
      //   Then handle that scheme in AuthGate's onAuthStateChange listener.
      await supabase.auth.resetPasswordForEmail(email);
      if (mounted) setState(() => _emailSent = true);
    } on AuthException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (_) {
      if (mounted) showErrorDialog(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoverColors.surfaceContainerLowest,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
          child: _emailSent ? _buildSuccessState() : _buildFormState(),
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Back ──────────────────────────────────────────────────
        IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: RoverColors.onSurface),
          onPressed: () => Navigator.of(context).pop(),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(height: 32),

        // ── Icon ──────────────────────────────────────────────────
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: RoverColors.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.lock_open_rounded, color: RoverColors.primary, size: 28),
        ),
        const SizedBox(height: 24),

        // ── Headline ──────────────────────────────────────────────
        Text('Forgot Password?', style: RoverText.headlineLg(color: RoverColors.primary)),
        const SizedBox(height: 8),
        Text(
          "Enter the email linked to your account. We'll send you a link to reset your password.",
          style: RoverText.bodyMd(color: RoverColors.textSecondary),
        ),
        const SizedBox(height: 36),

        // ── Email ─────────────────────────────────────────────────
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (_) => _handleSendLink(),
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 32),

        // ── CTA ───────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleSendLink,
            style: FilledButton.styleFrom(
              backgroundColor: RoverColors.primary,
              foregroundColor: RoverColors.onPrimary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: RoverText.titleSm(color: RoverColors.onPrimary)
                  .copyWith(letterSpacing: 1.2),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: RoverColors.onPrimary,
                    ),
                  )
                : const Text('SEND RESET LINK'),
          ),
        ),
        const SizedBox(height: 24),

        // ── Back to sign in ───────────────────────────────────────
        Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Back to Sign In',
              style: RoverText.labelMd(color: RoverColors.primary),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessState() {
    return Column(
      children: [
        const SizedBox(height: 60),

        // ── Icon ──────────────────────────────────────────────────
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: RoverColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: RoverColors.primary,
            size: 44,
          ),
        ),
        const SizedBox(height: 30),

        // ── Headline ──────────────────────────────────────────────
        Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: RoverText.headlineMd(color: RoverColors.primary),
        ),
        const SizedBox(height: 16),
        Text(
          'We sent a password reset link to\n${_emailController.text.trim()}',
          textAlign: TextAlign.center,
          style: RoverText.bodyMd(color: RoverColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          "Also check your spam folder if it doesn't arrive within a few minutes.",
          textAlign: TextAlign.center,
          style: RoverText.bodySm(color: RoverColors.outline),
        ),
        const SizedBox(height: 40),

        // ── Back to sign in ───────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: RoverColors.primary,
              side: const BorderSide(color: RoverColors.primary, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: RoverText.titleSm(color: RoverColors.primary)
                  .copyWith(letterSpacing: 1.2),
            ),
            child: const Text('BACK TO SIGN IN'),
          ),
        ),
        const SizedBox(height: 20),

        // ── Resend ────────────────────────────────────────────────
        TextButton(
          onPressed: _isLoading ? null : _handleSendLink,
          child: Text(
            "Didn't receive it? Resend",
            style: RoverText.labelMd(color: RoverColors.primary),
          ),
        ),
      ],
    );
  }
}
