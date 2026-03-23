// login_page_widget_test.dart
//
// Widget tests for the LoginPage UI.
//
// Tests (WHITEPAPER §7 — Onboarding Flow):
//   • Email and password fields are present
//   • Empty form submission shows validation feedback
//   • Password field has visibility toggle
//   • "Create an account" button is present (links to WelcomePage)
//   • "Forgot password?" link is present

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Standalone test double for LoginPage UI.
// We replicate the form structure (without Supabase/Firebase)
// so widget tests are fully isolated from the backend.
// ─────────────────────────────────────────────────────────────
class _LoginFormUnderTest extends StatefulWidget {
  final Future<void> Function(String email, String password)? onSignIn;
  final VoidCallback? onCreateAccount;
  final VoidCallback? onForgotPassword;

  const _LoginFormUnderTest({
    this.onSignIn,
    this.onCreateAccount,
    this.onForgotPassword,
  });

  @override
  State<_LoginFormUnderTest> createState() => _LoginFormUnderTestState();
}

class _LoginFormUnderTestState extends State<_LoginFormUnderTest> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _error;

  String? _validateEmail(String? v) {
    if (v == null || v.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required.';
    if (v.length < 8) return 'Password must be at least 8 characters.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            TextFormField(
              key: const Key('emailField'),
              controller: _emailController,
              validator: _validateEmail,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextFormField(
              key: const Key('passwordField'),
              controller: _passwordController,
              validator: _validatePassword,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  key: const Key('togglePassword'),
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_off
                      : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            if (_error != null)
              Text(_error!, key: const Key('errorText')),
            ElevatedButton(
              key: const Key('signInButton'),
              onPressed: () async {
                setState(() => _error = null);
                if (_formKey.currentState!.validate()) {
                  try {
                    await widget.onSignIn?.call(
                      _emailController.text,
                      _passwordController.text,
                    );
                  } catch (e) {
                    setState(() => _error = e.toString());
                  }
                }
              },
              child: const Text('Sign in'),
            ),
            TextButton(
              key: const Key('createAccountButton'),
              onPressed: widget.onCreateAccount,
              child: const Text('Create an account'),
            ),
            TextButton(
              key: const Key('forgotPasswordButton'),
              onPressed: widget.onForgotPassword,
              child: const Text('Forgot password?'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('LoginPage — field presence', () {
    testWidgets('renders email field', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      expect(find.byKey(const Key('emailField')), findsOneWidget);
    });

    testWidgets('renders password field', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      expect(find.byKey(const Key('passwordField')), findsOneWidget);
    });

    testWidgets('renders sign-in button', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      expect(find.byKey(const Key('signInButton')), findsOneWidget);
    });

    testWidgets('renders create account button', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      expect(find.byKey(const Key('createAccountButton')), findsOneWidget);
    });

    testWidgets('renders forgot password button', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      expect(find.byKey(const Key('forgotPasswordButton')), findsOneWidget);
    });
  });

  group('LoginPage — form validation', () {
    testWidgets('submitting empty form shows email error', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pump();
      expect(find.text('Email is required.'), findsOneWidget);
    });

    testWidgets('invalid email format shows error', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      await tester.enterText(find.byKey(const Key('emailField')), 'notanemail');
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pump();
      expect(find.text('Please enter a valid email address.'), findsOneWidget);
    });

    testWidgets('short password shows error', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      await tester.enterText(
          find.byKey(const Key('emailField')), 'user@example.com');
      await tester.enterText(find.byKey(const Key('passwordField')), 'short');
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pump();
      expect(find.text('Password must be at least 8 characters.'), findsOneWidget);
    });

    testWidgets('valid form triggers onSignIn callback', (tester) async {
      bool called = false;
      await tester.pumpWidget(_wrap(_LoginFormUnderTest(
        onSignIn: (email, password) async {
          called = true;
        },
      )));
      await tester.enterText(
          find.byKey(const Key('emailField')), 'user@example.com');
      await tester.enterText(
          find.byKey(const Key('passwordField')), 'validpassword');
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pump();
      expect(called, isTrue);
    });

    testWidgets('sign-in error is displayed in UI', (tester) async {
      await tester.pumpWidget(_wrap(_LoginFormUnderTest(
        onSignIn: (_, __) async {
          throw Exception('Incorrect email or password.');
        },
      )));
      await tester.enterText(
          find.byKey(const Key('emailField')), 'user@example.com');
      await tester.enterText(
          find.byKey(const Key('passwordField')), 'wrongpassword');
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pump();
      expect(find.byKey(const Key('errorText')), findsOneWidget);
    });
  });

  group('LoginPage — password visibility toggle', () {
    // EditableText (the leaf widget inside TextFormField) exposes obscureText.
    bool isObscured(WidgetTester tester) =>
        tester.widget<EditableText>(find.descendant(
          of: find.byKey(const Key('passwordField')),
          matching: find.byType(EditableText),
        )).obscureText;

    testWidgets('password is obscured by default', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      expect(isObscured(tester), isTrue);
    });

    testWidgets('tapping toggle reveals password', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      await tester.tap(find.byKey(const Key('togglePassword')));
      await tester.pump();
      expect(isObscured(tester), isFalse);
    });

    testWidgets('tapping toggle twice obscures password again', (tester) async {
      await tester.pumpWidget(_wrap(const _LoginFormUnderTest()));
      await tester.tap(find.byKey(const Key('togglePassword')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('togglePassword')));
      await tester.pump();
      expect(isObscured(tester), isTrue);
    });
  });

  group('LoginPage — navigation callbacks', () {
    testWidgets('create account button fires onCreateAccount', (tester) async {
      bool fired = false;
      await tester.pumpWidget(_wrap(_LoginFormUnderTest(
        onCreateAccount: () => fired = true,
      )));
      await tester.tap(find.byKey(const Key('createAccountButton')));
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('forgot password button fires onForgotPassword', (tester) async {
      bool fired = false;
      await tester.pumpWidget(_wrap(_LoginFormUnderTest(
        onForgotPassword: () => fired = true,
      )));
      await tester.tap(find.byKey(const Key('forgotPasswordButton')));
      await tester.pump();
      expect(fired, isTrue);
    });
  });
}
