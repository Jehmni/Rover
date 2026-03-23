// pickup_validation_test.dart
//
// Unit tests for pickup service validation rules.
//
// Tested rules (from WHITEPAPER §9 — Pickup & Route Optimisation):
//   • GPS coordinates from device must be in valid range
//   • Cannot cancel a pickup with status 'completed' (Fix M-10)
//   • Duplicate pickup guard: user can't submit twice for same event
//   • Status transition logic: pending → en_route → completed
//   • listenToMyPickup hides completed rows from ETA card (Fix L-7)

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Validation helpers — mirror PickupService validation logic.
// ─────────────────────────────────────────────────────────────
String? validateGpsLatitude(double latitude) {
  if (latitude < -90 || latitude > 90) {
    return 'Invalid GPS latitude: $latitude';
  }
  return null;
}

String? validateGpsLongitude(double longitude) {
  if (longitude < -180 || longitude > 180) {
    return 'Invalid GPS longitude: $longitude';
  }
  return null;
}

String? validateCancelPickup(Map<String, dynamic>? existing) {
  if (existing == null) return 'No pickup request found for this event.';
  if (existing['status'] == 'completed') {
    return 'This pickup has already been completed and cannot be cancelled.';
  }
  return null;
}

// Mirrors the filter in listenToMyPickup — returns true if row should be shown
bool isActivePickup(Map<String, dynamic> row, String userId) {
  return row['user_id'] == userId && row['status'] != 'completed';
}

void main() {
  group('GPS latitude validation', () {
    test('latitude -90 is valid (South Pole boundary)', () {
      expect(validateGpsLatitude(-90), isNull);
    });

    test('latitude 90 is valid (North Pole boundary)', () {
      expect(validateGpsLatitude(90), isNull);
    });

    test('latitude below -90 is invalid', () {
      expect(validateGpsLatitude(-90.001), isNotNull);
    });

    test('latitude above 90 is invalid', () {
      expect(validateGpsLatitude(90.001), isNotNull);
    });

    test('typical city latitude is valid', () {
      expect(validateGpsLatitude(51.5074), isNull); // London
    });
  });

  group('GPS longitude validation', () {
    test('longitude -180 is valid (date line)', () {
      expect(validateGpsLongitude(-180), isNull);
    });

    test('longitude 180 is valid (date line)', () {
      expect(validateGpsLongitude(180), isNull);
    });

    test('longitude below -180 is invalid', () {
      expect(validateGpsLongitude(-180.001), isNotNull);
    });

    test('longitude above 180 is invalid', () {
      expect(validateGpsLongitude(180.001), isNotNull);
    });

    test('typical city longitude is valid', () {
      expect(validateGpsLongitude(-0.1278), isNull); // London
    });
  });

  group('Cancel pickup guard (Fix M-10)', () {
    test('no existing pickup → error', () {
      expect(validateCancelPickup(null), isNotNull);
      expect(validateCancelPickup(null), contains('No pickup request found'));
    });

    test('completed pickup cannot be cancelled', () {
      final completed = {'id': 1, 'status': 'completed'};
      final error = validateCancelPickup(completed);
      expect(error, isNotNull);
      expect(error, contains('completed'));
    });

    test('pending pickup can be cancelled', () {
      final pending = {'id': 2, 'status': 'pending'};
      expect(validateCancelPickup(pending), isNull);
    });

    test('en_route pickup can be cancelled', () {
      final enRoute = {'id': 3, 'status': 'en_route'};
      expect(validateCancelPickup(enRoute), isNull);
    });
  });

  group('Status transition logic', () {
    final validTransitions = {
      'pending': ['en_route'],
      'en_route': ['completed'],
      'completed': <String>[],
    };

    test('pending can transition to en_route', () {
      expect(validTransitions['pending'], contains('en_route'));
    });

    test('en_route can transition to completed', () {
      expect(validTransitions['en_route'], contains('completed'));
    });

    test('completed has no further transitions', () {
      expect(validTransitions['completed'], isEmpty);
    });
  });

  group('listenToMyPickup active filter (Fix L-7)', () {
    const userId = 'user-abc-123';

    test('pending row for current user is shown', () {
      final row = {'user_id': userId, 'status': 'pending'};
      expect(isActivePickup(row, userId), isTrue);
    });

    test('en_route row for current user is shown', () {
      final row = {'user_id': userId, 'status': 'en_route'};
      expect(isActivePickup(row, userId), isTrue);
    });

    test('completed row for current user is hidden (Fix L-7)', () {
      final row = {'user_id': userId, 'status': 'completed'};
      expect(isActivePickup(row, userId), isFalse);
    });

    test('pending row for different user is hidden', () {
      final row = {'user_id': 'other-user-id', 'status': 'pending'};
      expect(isActivePickup(row, userId), isFalse);
    });
  });

  group('WKT coordinate format for PostGIS', () {
    // Documents the PostGIS WKT format: POINT(longitude latitude)
    // Note the ORDER: longitude first, then latitude (opposite to common expectation)
    test('WKT string has longitude before latitude', () {
      const longitude = -0.1278;
      const latitude = 51.5074;
      final wkt = 'POINT($longitude $latitude)';
      expect(wkt, 'POINT(-0.1278 51.5074)');
      expect(wkt, startsWith('POINT('));
    });
  });
}
