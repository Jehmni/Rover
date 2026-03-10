import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import '../main.dart';
import '../widgets/auth_dialog.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

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

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool obscure,
    required VoidCallback onToggle,
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
            style: const TextStyle(color: Colors.white, fontFamily: 'OpenSans'),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 14),
              prefixIcon: Icon(icon, color: Colors.white),
              suffixIcon: GestureDetector(
                onTap: onToggle,
                child: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  color: Colors.white70,
                ),
              ),
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
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Container(
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
            ),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_reset, color: Colors.white, size: 48),
                    const SizedBox(height: 20),
                    const Text(
                      'Set New Password',
                      style: TextStyle(
                        color: Colors.white,
                        fontFamily: 'OpenSans',
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Choose a strong password for your account.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontFamily: 'OpenSans',
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildPasswordField(
                      controller: _passwordController,
                      label: 'New Password',
                      hint: 'At least 8 characters',
                      icon: Icons.lock,
                      obscure: _obscureNew,
                      onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    _buildPasswordField(
                      controller: _confirmController,
                      label: 'Confirm Password',
                      hint: 'Repeat your new password',
                      icon: Icons.lock_outline,
                      obscure: _obscureConfirm,
                      onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _handleUpdate,
                        style: ElevatedButton.styleFrom(
                          elevation: 5,
                          padding: const EdgeInsets.all(15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Color(0xFF527DAA))
                            : const Text(
                                'UPDATE PASSWORD',
                                style: TextStyle(
                                  color: Color(0xFF527DAA),
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
          ],
        ),
      ),
    );
  }
}
