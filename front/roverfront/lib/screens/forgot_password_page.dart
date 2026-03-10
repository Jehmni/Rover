import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../constants.dart';
import '../main.dart';
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
      // redirectTo must be added to Supabase:
      //   Authentication → URL Configuration → Redirect URLs
      // Add: http://localhost:* for local dev, or your production URL.
      final redirectTo = '${Uri.base.origin}/';
      await supabase.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
      if (mounted) setState(() => _emailSent = true);
    } on AuthException catch (e) {
      if (mounted) showErrorDialog(context, e.message);
    } catch (_) {
      if (mounted) showErrorDialog(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static const _gradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF73AEF5), Color(0xFF61A4F1), Color(0xFF478DE0), Color(0xFF398AE5)],
      stops: [0.1, 0.4, 0.7, 0.9],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Container(height: double.infinity, width: double.infinity, decoration: _gradient),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
                child: _emailSent ? _buildSuccessState() : _buildFormState(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 40),
        const Text(
          'Forgot Password?',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'OpenSans',
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Enter the email linked to your account. We\'ll send you a link to reset your password.',
          style: TextStyle(
            color: Colors.white70,
            fontFamily: 'OpenSans',
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 40),
        const Text('Email', style: kLabelStyle),
        const SizedBox(height: 10),
        Container(
          alignment: Alignment.centerLeft,
          decoration: kBoxDecorationStyle,
          height: 60,
          child: TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontFamily: 'OpenSans'),
            onSubmitted: (_) => _handleSendLink(),
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(top: 14),
              prefixIcon: Icon(Icons.email, color: Colors.white),
              hintText: 'Enter your email',
              hintStyle: kHintTextStyle,
            ),
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleSendLink,
            style: ElevatedButton.styleFrom(
              elevation: 5,
              padding: const EdgeInsets.all(15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Color(0xFF527DAA))
                : const Text(
                    'SEND RESET LINK',
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
        const SizedBox(height: 24),
        Center(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const Text(
              'Back to Sign In',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                decoration: TextDecoration.underline,
                decorationColor: Colors.white70,
              ),
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
        const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 80),
        const SizedBox(height: 30),
        const Text(
          'Check Your Email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'OpenSans',
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'We sent a password reset link to\n${_emailController.text.trim()}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontFamily: 'OpenSans',
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Also check your spam folder if it doesn\'t arrive within a few minutes.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white54,
            fontFamily: 'OpenSans',
            fontSize: 12,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white, width: 2),
              padding: const EdgeInsets.all(15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: const Text(
              'BACK TO SIGN IN',
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
        const SizedBox(height: 20),
        TextButton(
          onPressed: _isLoading ? null : _handleSendLink,
          child: const Text(
            "Didn't receive it? Resend",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }
}
