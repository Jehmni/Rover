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
import '../constants.dart';
import '../services/auth_service.dart';
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
  bool _isLoading = false;

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
        // After confirming, user signs in and is routed to OrgSetupPage.
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: kLabelStyle),
        const SizedBox(height: 10),
        Container(
          alignment: Alignment.centerLeft,
          decoration: kBoxDecorationStyle,
          height: 60,
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontFamily: 'OpenSans'),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 14),
              prefixIcon: Icon(icon, color: Colors.white),
              hintText: hint,
              hintStyle: kHintTextStyle,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        height: double.infinity,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF73AEF5),
              Color(0xFF61A4F1),
              Color(0xFF478DE0),
              Color(0xFF398AE5),
            ],
            stops: [0.1, 0.4, 0.7, 0.9],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
          child: Column(
            children: [
              const Text(
                'Create Account',
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'OpenSans',
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // ── Org banner (deep-link context) ──────────────────────
              if (widget.orgToken != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.link,
                          color: Colors.white70, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.orgName != null
                              ? 'Joining: ${widget.orgName}'
                              : 'You will join an organisation on the next step.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Text(
                  'You will link your organisation on the next step.',
                  style: TextStyle(
                    color: Colors.white70,
                    fontFamily: 'OpenSans',
                    fontSize: 13,
                  ),
                ),

              const SizedBox(height: 30),
              _buildTextField(
                controller: _nameController,
                label: 'Full Name',
                hint: 'Enter your full name',
                icon: Icons.person,
              ),
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'Enter your email',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
              ),
              _buildTextField(
                controller: _passwordController,
                label: 'Password',
                hint: 'At least 8 characters',
                icon: Icons.lock,
                obscure: true,
              ),
              _buildTextField(
                controller: _phoneController,
                label: 'Phone (optional)',
                hint: '+1 555 000 0000',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    elevation: 5,
                    padding: const EdgeInsets.all(15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                          color: Color(0xFF527DAA))
                      : const Text(
                          'CREATE ACCOUNT',
                          style: TextStyle(
                            color: Color(0xFF527DAA),
                            letterSpacing: 1.5,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'OpenSans',
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: const [
                  Expanded(
                      child: Divider(color: Colors.white54, thickness: 0.8)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'HAVE AN ACCOUNT?',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Expanded(
                      child: Divider(color: Colors.white54, thickness: 0.8)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 2),
                    padding: const EdgeInsets.all(15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'SIGN IN',
                    style: TextStyle(
                      color: Colors.white,
                      letterSpacing: 1.5,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'OpenSans',
                    ),
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
