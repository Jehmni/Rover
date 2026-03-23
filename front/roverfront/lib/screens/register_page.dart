// register_page.dart
//
// Collects name, email, password and optional phone.
// Role is set by the WelcomePage card tap — never shown as a picker.
// After registration, routes to OrgSetupPage to link the organisation.
//
// Constructor params:
//   role     — 'admin' | 'driver' | 'user'  (from WelcomePage card)
//   orgToken — UUID from deep link (pre-fills OrgSetupPage join field)
//   orgName  — resolved org name (shown in banner if arriving via link)

import 'package:flutter/material.dart';
import '../main.dart' show PendingLink;
import '../services/auth_service.dart';
import '../theme/rover_theme.dart';
import '../widgets/auth_dialog.dart';
import 'org_setup_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    this.role = 'user',
    this.orgToken,
    this.orgName,
  });

  /// Role pre-selected from WelcomePage. Never displayed to the user.
  final String role;

  /// Org token from a deep link (rover.app/join/TOKEN). Passed through
  /// to OrgSetupPage so the join step is pre-filled.
  final String? orgToken;

  /// Resolved org name to display in the banner (may be null).
  final String? orgName;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController    = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController     = TextEditingController();
  final _phoneController    = TextEditingController();
  bool _isLoading    = false;
  bool _obscurePass  = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    setState(() => _isLoading = true);
    try {
      // Fix M-2: persist the org token NOW so it survives an app kill.
      // If email confirmation is required the user may close the app,
      // confirm their email, and relaunch — the token will be waiting.
      if (widget.orgToken != null) {
        await PendingLink.setToken(widget.orgToken!);
        if (widget.orgName != null) PendingLink.orgName = widget.orgName;
      }

      final needsConfirmation = await AuthService.register(
        email:    _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        phone:    _phoneController.text.trim().isEmpty
                      ? null
                      : _phoneController.text.trim(),
      );
      if (!mounted) return;

      if (needsConfirmation) {
        // Email confirmation required.
        // Token is now on disk — user can kill the app, confirm their
        // email, and relaunch. On next cold start PendingLink.loadFromDisk()
        // will restore the token and OrgSetupPage will be pre-filled.
        showInfoDialog(
          context,
          title: 'Check Your Email',
          message:
              'Account created! We sent a confirmation link to '
              '${_emailController.text.trim()}.\n\n'
              'Click the link in that email, then sign in here. '
              "Don't forget to check your spam folder.\n\n"
              'You will be asked to link your organisation after signing in.',
          buttonLabel: 'OK',
        );
      } else {
        // Session active — route straight to OrgSetupPage.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => OrgSetupPage(
              initialRole: widget.role,
              orgToken:    widget.orgToken,
              orgName:     widget.orgName,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          e.toString().replaceFirst('Exception: ', ''),
        );
      }
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
              // ── Headline ─────────────────────────────────────────────
              Text(
                'Create Account',
                style: RoverText.headlineLg(color: RoverColors.primary),
              ),
              const SizedBox(height: 8),

              // ── Subtitle / org banner ─────────────────────────────────
              if (widget.orgToken != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: RoverColors.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link_rounded,
                          color: RoverColors.primary, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.orgName != null
                              ? 'Joining: ${widget.orgName}'
                              : 'You will join an organisation on the next step.',
                          style: RoverText.bodySm(color: RoverColors.primary),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Text(
                  'You will link your organisation on the next step.',
                  style: RoverText.bodyMd(color: RoverColors.textSecondary),
                ),

              const SizedBox(height: 32),

              // ── Full Name ─────────────────────────────────────────────
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 16),

              // ── Email ─────────────────────────────────────────────────
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 16),

              // ── Password ──────────────────────────────────────────────
              TextField(
                controller: _passwordController,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePass ? Icons.visibility_off : Icons.visibility,
                      color: RoverColors.outline,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Phone (optional) ──────────────────────────────────────
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                ),
              ),
              const SizedBox(height: 32),

              // ── Primary CTA ───────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: FilledButton.styleFrom(
                    backgroundColor: RoverColors.primary,
                    foregroundColor: RoverColors.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
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
                      : const Text('CREATE ACCOUNT'),
                ),
              ),
              const SizedBox(height: 24),

              // ── "Have an account?" divider ────────────────────────────
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'HAVE AN ACCOUNT?',
                      style: RoverText.labelSm(color: RoverColors.textSecondary),
                    ),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 24),

              // ── Sign in link ──────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: RoverColors.primary,
                    side: const BorderSide(
                        color: RoverColors.primary, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: RoverText.titleSm(color: RoverColors.primary)
                        .copyWith(letterSpacing: 1.2),
                  ),
                  child: const Text('SIGN IN'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
