import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../theme/rover_theme.dart';
import '../widgets/auth_dialog.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _isLoading     = false;
  bool _obscureNew    = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    final password = _passwordController.text;
    final confirm  = _confirmController.text;

    if (password.length < 8) {
      showErrorDialog(context, 'Password must be at least 8 characters.');
      return;
    }
    if (password != confirm) {
      showErrorDialog(context, 'Passwords do not match. Please re-enter both fields.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: password));
      await supabase.auth.signOut();
      if (!mounted) return;
      showInfoDialog(
        context,
        title: 'Password Updated',
        message:
            'Your password has been updated successfully. Please sign in with your new password.',
        buttonLabel: 'SIGN IN',
        onDismiss: () =>
            Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false),
      );
    } on AuthException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (_) {
      if (mounted) showErrorDialog(context, 'Failed to update password. Please try again.');
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon ─────────────────────────────────────────────────
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: RoverColors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.lock_reset, color: RoverColors.primary, size: 28),
              ),
              const SizedBox(height: 24),

              // ── Headline ─────────────────────────────────────────────
              Text('Set New Password', style: RoverText.headlineLg(color: RoverColors.primary)),
              const SizedBox(height: 8),
              Text(
                'Choose a strong password for your account.',
                style: RoverText.bodyMd(color: RoverColors.textSecondary),
              ),
              const SizedBox(height: 36),

              // ── New password ─────────────────────────────────────────
              TextField(
                controller: _passwordController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off : Icons.visibility,
                      color: RoverColors.outline,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Confirm password ─────────────────────────────────────
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                      color: RoverColors.outline,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ── CTA ───────────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _isLoading ? null : _handleUpdate,
                  style: FilledButton.styleFrom(
                    backgroundColor: RoverColors.primary,
                    foregroundColor: RoverColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
                      : const Text('UPDATE PASSWORD'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
