// auth_service.dart
//
// Handles Supabase Auth signup and login.
//
// Registration flow (v2 — multi-tenant):
//   1. signUp() creates the auth user and the trigger creates a
//      minimal profile row (role='user', org_id=NULL).
//   2. The Flutter app immediately calls OrgService.createOrganisationAndAdmin()
//      or OrgService.joinWithCode() to set the org and role.
//   3. If email confirmation is required, the user confirms their
//      email and signs in; login() returns 'no_org' which routes
//      them to OrgSetupPage to complete step 2.
//
// Security:
//   - Passwords are NEVER stored or compared as plaintext.
//   - Role assignment happens server-side via SECURITY DEFINER RPCs.
//   - Rate limiting is handled by Supabase Auth automatically.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class AuthService {
  // ─────────────────────────────────────────────────────────
  // REGISTER
  //
  // Creates the auth user. Does NOT set a role or org — that
  // is done via OrgService after this call succeeds.
  //
  // Returns true  → email confirmation required; caller shows
  //                 "check your email" UI and waits for login.
  // Returns false → session is active; caller must immediately
  //                 call OrgService.createOrganisationAndAdmin()
  //                 or OrgService.joinWithCode().
  // ─────────────────────────────────────────────────────────
  static Future<bool> register({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      throw Exception('Please enter a valid email address.');
    }
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }
    if (fullName.trim().isEmpty) {
      throw Exception('Please enter your full name.');
    }
    if (fullName.trim().length > 100) {
      throw Exception('Full name must be 100 characters or fewer.');
    }
    if (phone != null &&
        phone.isNotEmpty &&
        !RegExp(r'^[0-9 +\-]+$').hasMatch(phone)) {
      throw Exception('Phone number may only contain digits, spaces, + and -.');
    }

    // ── Create auth user ───────────────────────────────────
    // Pass full_name in metadata so the handle_new_user trigger
    // can populate the profile row before the RPC is called.
    late AuthResponse response;
    try {
      response = await supabase.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': fullName.trim()},
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('already exists') ||
          msg.contains('user already')) {
        throw Exception(
          'An account with this email already exists. Try signing in instead.',
        );
      }
      throw Exception(e.message);
    }

    if (response.user == null) {
      throw Exception('Registration failed. Please try again.');
    }

    if (response.session == null) {
      // Email confirmation required — profile trigger already ran.
      // The user must confirm their email, sign in, and will be
      // routed to OrgSetupPage (login() returns 'no_org').
      return true;
    }

    // Session is active — trigger already created the profile row.
    // The register_page will immediately route to OrgSetupPage.
    return false;
  }

  // ─────────────────────────────────────────────────────────
  // LOGIN
  //
  // Returns:
  //   'admin'    → navigate to AdminHomePage
  //   'driver'   → navigate to DriverHomePage
  //   'user'     → navigate to UserHomePage
  //   'no_org'   → navigate to OrgSetupPage (org not yet linked)
  // ─────────────────────────────────────────────────────────
  static Future<String> login({
    required String email,
    required String password,
  }) async {
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      throw Exception('Please enter a valid email address.');
    }
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }

    late AuthResponse response;
    try {
      response = await supabase.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('invalid login credentials') ||
          msg.contains('invalid email or password') ||
          msg.contains('wrong password') ||
          msg.contains('no user found')) {
        throw Exception(
          'Incorrect email or password. Please check your credentials and try again.',
        );
      }
      if (msg.contains('email not confirmed')) {
        throw Exception(
          'Your email address has not been confirmed yet. '
          'Please check your inbox (and spam folder) for the confirmation link.',
        );
      }
      if (msg.contains('too many requests') || msg.contains('rate limit')) {
        throw Exception(
          'Too many sign-in attempts. Please wait a few minutes and try again.',
        );
      }
      throw Exception(e.message);
    }

    if (response.user == null) {
      throw Exception(
        'Sign-in failed. Please check your credentials and try again.',
      );
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select('role, org_id')
          .eq('id', response.user!.id)
          .single();

      // ── Org not yet linked ─────────────────────────────
      // This happens after email confirmation, or if org setup
      // was interrupted. OrgSetupPage will complete the setup.
      if (profile['org_id'] == null) {
        return 'no_org';
      }

      await _registerFcmToken();
      return profile['role'] as String;
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') {
        return await _healMissingProfile(response.user!);
      }
      await supabase.auth.signOut();
      throw Exception(
        'Your account was found but we could not load your profile. '
        'Please try again.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────
  // HEAL MISSING PROFILE
  // Creates a minimal profile row if the trigger missed it.
  // org_id is still null — caller routes to OrgSetupPage.
  // ─────────────────────────────────────────────────────────
  static Future<String> _healMissingProfile(User user) async {
    final meta = user.userMetadata ?? {};
    final fullName = (meta['full_name'] as String?) ?? '';

    try {
      await supabase.from('profiles').insert({
        'id': user.id,
        'role': 'user',
        'full_name': fullName,
        // org_id intentionally null — OrgSetupPage will set it
      });
      return 'no_org';
    } on PostgrestException catch (insertErr) {
      // Row may have appeared concurrently — try reading it
      try {
        final profile = await supabase
            .from('profiles')
            .select('role, org_id')
            .eq('id', user.id)
            .single();
        if (profile['org_id'] == null) return 'no_org';
        await _registerFcmToken();
        return profile['role'] as String;
      } catch (_) {}

      await supabase.auth.signOut();
      throw Exception(
        'Your account was found but profile setup failed '
        '(${insertErr.message}). Please contact support.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────
  // LOGOUT
  // ─────────────────────────────────────────────────────────
  static Future<void> logout() async {
    await supabase.auth.signOut();
  }

  // ─────────────────────────────────────────────────────────
  // CURRENT USER
  // ─────────────────────────────────────────────────────────
  static User? get currentUser => supabase.auth.currentUser;

  // ─────────────────────────────────────────────────────────
  // FCM TOKEN REGISTRATION (non-fatal)
  // ─────────────────────────────────────────────────────────
  static Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && currentUser != null) {
        await supabase
            .from('profiles')
            .update({'fcm_token': token})
            .eq('id', currentUser!.id);
      }
    } catch (_) {
      // Firebase may not be configured — skip silently
    }
  }
}
