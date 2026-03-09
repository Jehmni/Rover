// auth_service.dart
//
// Replaces ALL HTTP calls to:
//   POST /api/users/register
//   POST /api/drivers/register
//   POST /api/admins/register   ← no longer a public endpoint
//   POST /api/login
//
// Security fixes applied vs rover.py:
//   - Passwords are NEVER stored or compared as plaintext.
//     Supabase Auth handles bcrypt hashing internally.
//   - Admin registration is NOT possible from the public app.
//     Admins are created via Supabase Dashboard only.
//   - Rate limiting on auth is handled by Supabase Auth automatically.

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class AuthService {
  // ─────────────────────────────────────────────────────────
  // REGISTER
  // Accepts role 'user' or 'driver' only. The 'admin' role
  // cannot be assigned from this method — see schema.sql for
  // the manual INSERT comment.
  // ─────────────────────────────────────────────────────────
  static Future<void> register({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phone,
  }) async {
    // Client-side validation (Phase 6 rules)
    if (role == 'admin') {
      throw Exception('Admin accounts cannot be created from the app.');
    }
    if (role != 'user' && role != 'driver') {
      throw Exception('Role must be "user" or "driver".');
    }
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

    // Create auth user — Supabase hashes the password; we never see it
    final response = await supabase.auth.signUp(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw Exception('Registration failed. Please try again.');
    }

    // Insert matching profile row (linked by UUID to auth.users)
    await supabase.from('profiles').insert({
      'id': response.user!.id,
      'role': role,
      'full_name': fullName.trim(),
      if (phone != null && phone.isNotEmpty) 'phone': phone.trim(),
    });
  }

  // ─────────────────────────────────────────────────────────
  // LOGIN
  // Works for all roles. Returns the role string so the caller
  // can navigate to the correct home screen.
  //
  // Fix vs rover.py Bug 2: BusDriver had no username/password
  // columns and caused an InvalidRequestError on every login.
  // Here we query profiles (which has the role), not the
  // non-existent BusDriver.username field.
  // ─────────────────────────────────────────────────────────
  static Future<String> login({
    required String email,
    required String password,
  }) async {
    // Client-side validation
    if (email.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email)) {
      throw Exception('Please enter a valid email address.');
    }
    if (password.length < 8) {
      throw Exception('Password must be at least 8 characters.');
    }

    final response = await supabase.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );

    if (response.user == null) {
      throw Exception('Invalid credentials. Please try again.');
    }

    // Fetch role from profiles table to determine navigation target
    final profile = await supabase
        .from('profiles')
        .select('role')
        .eq('id', response.user!.id)
        .single();

    // Register FCM token after successful login (non-fatal if it fails)
    await _registerFcmToken();

    return profile['role'] as String; // 'user' | 'driver' | 'admin'
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
  // FCM TOKEN REGISTRATION
  // Stores the device push token on the profile so Edge Functions
  // can send targeted notifications. Non-fatal — if Firebase is
  // not configured, this silently skips.
  // Requires: ALTER TABLE public.profiles ADD COLUMN fcm_token text;
  // (already included in schema.sql)
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
      // Firebase may not be configured in all environments — skip silently
    }
  }
}
