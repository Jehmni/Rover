// auth_validation_test.dart
//
// Unit tests for all client-side validation rules in AuthService.
// These tests exercise the SAME validation logic as the service
// without making any network calls (validation throws before Supabase).
//
// Tested rules (from WHITEPAPER §7 — Onboarding Flow):
//   • Email must match r'^[^@]+@[^@]+\.[^@]+'
//   • Password must be >= 8 characters
//   • Full name must not be empty and <= 100 characters
//   • Phone (if provided) may only contain digits, spaces, + and -

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Validation helpers — extracted from AuthService to allow pure
// unit testing without Supabase / Firebase initialisation.
// If AuthService validation changes, update these too.
// ─────────────────────────────────────────────────────────────
final _emailRe = RegExp(r'^[^@]+@[^@]+\.[^@]+');
final _phoneRe = RegExp(r'^[0-9 +\-]+$');

String? validateEmail(String email) {
  if (email.isEmpty || !_emailRe.hasMatch(email)) {
    return 'Please enter a valid email address.';
  }
  return null;
}

String? validatePassword(String password) {
  if (password.length < 8) return 'Password must be at least 8 characters.';
  return null;
}

String? validateFullName(String fullName) {
  if (fullName.trim().isEmpty) return 'Please enter your full name.';
  if (fullName.trim().length > 100) {
    return 'Full name must be 100 characters or fewer.';
  }
  return null;
}

String? validatePhone(String? phone) {
  if (phone != null && phone.isNotEmpty && !_phoneRe.hasMatch(phone)) {
    return 'Phone number may only contain digits, spaces, + and -.';
  }
  return null;
}

void main() {
  group('Email validation', () {
    test('empty email is invalid', () {
      expect(validateEmail(''), isNotNull);
    });

    test('email without @ is invalid', () {
      expect(validateEmail('userexample.com'), isNotNull);
    });

    test('email without domain is invalid', () {
      expect(validateEmail('user@'), isNotNull);
    });

    test('email without dot in domain is invalid', () {
      expect(validateEmail('user@nodot'), isNotNull);
    });

    test('plain string is invalid', () {
      expect(validateEmail('notanemail'), isNotNull);
    });

    test('valid email passes', () {
      expect(validateEmail('user@example.com'), isNull);
    });

    test('email with subdomain passes', () {
      expect(validateEmail('user@mail.example.co.uk'), isNull);
    });

    test('email with + alias passes', () {
      expect(validateEmail('user+tag@example.com'), isNull);
    });
  });

  group('Password validation', () {
    test('empty password fails', () {
      expect(validatePassword(''), isNotNull);
    });

    test('7-character password fails', () {
      expect(validatePassword('short12'), isNotNull);
    });

    test('exactly 8 characters passes', () {
      expect(validatePassword('exactly8'), isNull);
    });

    test('long password passes', () {
      expect(validatePassword('a very long secure password 123!'), isNull);
    });
  });

  group('Full name validation', () {
    test('empty name fails', () {
      expect(validateFullName(''), isNotNull);
    });

    test('whitespace-only name fails', () {
      expect(validateFullName('   '), isNotNull);
    });

    test('name over 100 characters fails', () {
      final longName = 'A' * 101;
      expect(validateFullName(longName), isNotNull);
    });

    test('exactly 100 characters passes', () {
      final exactName = 'A' * 100;
      expect(validateFullName(exactName), isNull);
    });

    test('normal name passes', () {
      expect(validateFullName('John Smith'), isNull);
    });

    test('name with leading/trailing spaces passes (trimmed)', () {
      expect(validateFullName('  Alice  '), isNull);
    });
  });

  group('Phone validation', () {
    test('null phone passes (optional field)', () {
      expect(validatePhone(null), isNull);
    });

    test('empty phone passes (optional field)', () {
      expect(validatePhone(''), isNull);
    });

    test('digits-only phone passes', () {
      expect(validatePhone('07911123456'), isNull);
    });

    test('international format +44 passes', () {
      expect(validatePhone('+44 7911 123456'), isNull);
    });

    test('phone with hyphens passes', () {
      expect(validatePhone('07-911-123456'), isNull);
    });

    test('phone with letters fails', () {
      expect(validatePhone('0800-ROVER1'), isNotNull);
    });

    test('phone with special chars fails', () {
      expect(validatePhone('(0800) 123456'), isNotNull);
    });
  });
}
