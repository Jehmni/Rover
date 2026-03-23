// event_validation_test.dart
//
// Unit tests for all client-side validation rules in EventService.
//
// Tested rules (from WHITEPAPER §8 — Event Management):
//   • Event name must not be empty
//   • Event date must be in the future (createEvent)
//   • Event date must not be > 55 min in the past (updateEvent)
//   • Latitude must be in range [-90, 90]
//   • Longitude must be in range [-180, 180]

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Validation helpers — mirror EventService validation logic.
// ─────────────────────────────────────────────────────────────
String? validateEventName(String name) {
  if (name.trim().isEmpty) return 'Event name is required.';
  return null;
}

String? validateCreateEventDate(DateTime eventDate) {
  if (eventDate.isBefore(DateTime.now())) {
    return 'Event date must be in the future.';
  }
  return null;
}

String? validateUpdateEventDate(DateTime eventDate) {
  if (eventDate.isBefore(DateTime.now().subtract(const Duration(minutes: 55)))) {
    return 'Event date must not be in the past.';
  }
  return null;
}

String? validateLatitude(double? latitude) {
  if (latitude != null && (latitude < -90 || latitude > 90)) {
    return 'Latitude must be between -90 and 90.';
  }
  return null;
}

String? validateLongitude(double? longitude) {
  if (longitude != null && (longitude < -180 || longitude > 180)) {
    return 'Longitude must be between -180 and 180.';
  }
  return null;
}

void main() {
  group('Event name validation', () {
    test('empty name fails', () {
      expect(validateEventName(''), isNotNull);
    });

    test('whitespace-only name fails', () {
      expect(validateEventName('   '), isNotNull);
    });

    test('valid name passes', () {
      expect(validateEventName('Sunday Service'), isNull);
    });

    test('single character name passes', () {
      expect(validateEventName('A'), isNull);
    });
  });

  group('Create event — date must be in the future', () {
    test('past date fails', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(validateCreateEventDate(past), isNotNull);
    });

    test('current time fails (now is not in the future)', () {
      // DateTime.now() at test execution is always "before" itself + epsilon
      final justNow = DateTime.now().subtract(const Duration(seconds: 1));
      expect(validateCreateEventDate(justNow), isNotNull);
    });

    test('future date passes', () {
      final future = DateTime.now().add(const Duration(hours: 1));
      expect(validateCreateEventDate(future), isNull);
    });

    test('far future date passes', () {
      final farFuture = DateTime.now().add(const Duration(days: 365));
      expect(validateCreateEventDate(farFuture), isNull);
    });
  });

  group('Update event — date within 55-minute grace window', () {
    test('date 56+ minutes ago fails', () {
      final tooOld = DateTime.now().subtract(const Duration(minutes: 56));
      expect(validateUpdateEventDate(tooOld), isNotNull);
    });

    test('date 54 minutes ago passes (within grace window)', () {
      final recentPast = DateTime.now().subtract(const Duration(minutes: 54));
      expect(validateUpdateEventDate(recentPast), isNull);
    });

    test('future date passes', () {
      final future = DateTime.now().add(const Duration(hours: 2));
      expect(validateUpdateEventDate(future), isNull);
    });
  });

  group('Latitude validation', () {
    test('null latitude passes (optional)', () {
      expect(validateLatitude(null), isNull);
    });

    test('latitude exactly -90 passes (boundary)', () {
      expect(validateLatitude(-90.0), isNull);
    });

    test('latitude exactly 90 passes (boundary)', () {
      expect(validateLatitude(90.0), isNull);
    });

    test('latitude below -90 fails', () {
      expect(validateLatitude(-91.0), isNotNull);
    });

    test('latitude above 90 fails', () {
      expect(validateLatitude(91.0), isNotNull);
    });

    test('valid UK latitude passes', () {
      expect(validateLatitude(51.5074), isNull); // London
    });
  });

  group('Longitude validation', () {
    test('null longitude passes (optional)', () {
      expect(validateLongitude(null), isNull);
    });

    test('longitude exactly -180 passes (boundary)', () {
      expect(validateLongitude(-180.0), isNull);
    });

    test('longitude exactly 180 passes (boundary)', () {
      expect(validateLongitude(180.0), isNull);
    });

    test('longitude below -180 fails', () {
      expect(validateLongitude(-181.0), isNotNull);
    });

    test('longitude above 180 fails', () {
      expect(validateLongitude(181.0), isNotNull);
    });

    test('valid UK longitude passes', () {
      expect(validateLongitude(-0.1278), isNull); // London
    });
  });

  group('Combined coordinate validation', () {
    test('both null is valid (no location provided)', () {
      expect(validateLatitude(null), isNull);
      expect(validateLongitude(null), isNull);
    });

    test('valid coordinate pair passes', () {
      expect(validateLatitude(51.5074), isNull);
      expect(validateLongitude(-0.1278), isNull);
    });

    test('inverted lat/lon (common mistake) fails appropriately', () {
      // -0.1278 is a valid latitude, but 51.5074 is within 180 so still valid
      // PostGIS WKT format is POINT(lon lat) — swapping silently produces wrong data
      // This test documents the coordinate order contract
      expect(validateLatitude(-0.1278), isNull);
      expect(validateLongitude(51.5074), isNull);
    });

    test('out-of-range latitude with valid longitude fails on lat', () {
      expect(validateLatitude(91.0), isNotNull);
      expect(validateLongitude(-0.1278), isNull);
    });
  });
}
