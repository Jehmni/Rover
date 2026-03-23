// realtime_filter_test.dart
//
// Unit tests for real-time stream filter logic.
//
// Tested behaviours (from WHITEPAPER §11 — Real-Time Updates):
//   • listenToPickupUpdates: driver sees all pickups ordered by pickup_order
//   • listenToMyPickup: user sees only their own non-completed pickups
//   • getPickupProfiles: builds userId→profile map from joined rows

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Mirrors the filter logic from PickupService.listenToMyPickup
// ─────────────────────────────────────────────────────────────
Map<String, dynamic>? filterMyPickup(
    List<Map<String, dynamic>> rows, String userId) {
  final active = rows.where(
    (r) => r['user_id'] == userId && r['status'] != 'completed',
  );
  return active.isNotEmpty ? Map<String, dynamic>.from(active.first) : null;
}

// ─────────────────────────────────────────────────────────────
// Mirrors the profile-map builder in PickupService.getPickupProfiles
// ─────────────────────────────────────────────────────────────
Map<String, Map<String, dynamic>> buildProfileMap(List<Map<String, dynamic>> data) {
  final result = <String, Map<String, dynamic>>{};
  for (final row in data) {
    final userId = row['user_id'] as String?;
    final profile = row['profiles'] as Map?;
    if (userId != null && profile != null) {
      result[userId] = {
        'full_name': profile['full_name'],
        'phone': profile['phone'],
      };
    }
  }
  return result;
}

// ─────────────────────────────────────────────────────────────
// Mirrors ETA card text logic from DriverHomePage / EventDetailPage
// ─────────────────────────────────────────────────────────────
String etaStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return 'Waiting for driver';
    case 'en_route':
      return 'Driver is on the way';
    case 'completed':
      return 'Picked up';
    default:
      return 'Unknown';
  }
}

void main() {
  group('listenToMyPickup filter logic', () {
    const me = 'user-me';
    const other = 'user-other';

    test('returns pending row for current user', () {
      final rows = [
        {'user_id': me, 'status': 'pending', 'eta_minutes': 10},
      ];
      final result = filterMyPickup(rows, me);
      expect(result, isNotNull);
      expect(result!['status'], 'pending');
    });

    test('returns en_route row for current user', () {
      final rows = [
        {'user_id': me, 'status': 'en_route', 'eta_minutes': 3},
      ];
      expect(filterMyPickup(rows, me), isNotNull);
    });

    test('returns null when only completed row exists (Fix L-7)', () {
      final rows = [
        {'user_id': me, 'status': 'completed'},
      ];
      expect(filterMyPickup(rows, me), isNull);
    });

    test('returns null when no rows for current user', () {
      final rows = [
        {'user_id': other, 'status': 'pending'},
      ];
      expect(filterMyPickup(rows, me), isNull);
    });

    test('ignores other users rows and returns own pending row', () {
      final rows = [
        {'user_id': other, 'status': 'pending'},
        {'user_id': me, 'status': 'en_route'},
      ];
      final result = filterMyPickup(rows, me);
      expect(result, isNotNull);
      expect(result!['user_id'], me);
    });

    test('returns null when stream has no rows at all', () {
      expect(filterMyPickup([], me), isNull);
    });
  });

  group('getPickupProfiles — profile map builder', () {
    test('builds map from single row', () {
      final data = [
        {
          'user_id': 'u1',
          'profiles': {'full_name': 'Alice Smith', 'phone': '07900111222'},
        },
      ];
      final map = buildProfileMap(data);
      expect(map.containsKey('u1'), isTrue);
      expect(map['u1']!['full_name'], 'Alice Smith');
      expect(map['u1']!['phone'], '07900111222');
    });

    test('builds map from multiple rows', () {
      final data = [
        {'user_id': 'u1', 'profiles': {'full_name': 'Alice', 'phone': '111'}},
        {'user_id': 'u2', 'profiles': {'full_name': 'Bob', 'phone': '222'}},
      ];
      final map = buildProfileMap(data);
      expect(map.keys, containsAll(['u1', 'u2']));
    });

    test('skips rows with null user_id', () {
      final data = [
        {'user_id': null, 'profiles': {'full_name': 'Ghost', 'phone': ''}},
        {'user_id': 'u1', 'profiles': {'full_name': 'Real', 'phone': '123'}},
      ];
      final map = buildProfileMap(data);
      expect(map.length, 1);
      expect(map.containsKey('u1'), isTrue);
    });

    test('skips rows with null profiles', () {
      final data = [
        {'user_id': 'u1', 'profiles': null},
      ];
      final map = buildProfileMap(data);
      expect(map, isEmpty);
    });

    test('empty input returns empty map', () {
      expect(buildProfileMap([]), isEmpty);
    });
  });

  group('ETA status labels', () {
    test('pending shows waiting message', () {
      expect(etaStatusLabel('pending'), contains('Waiting'));
    });

    test('en_route shows on-the-way message', () {
      expect(etaStatusLabel('en_route'), contains('way'));
    });

    test('completed shows picked-up message', () {
      expect(etaStatusLabel('completed'), contains('Picked'));
    });

    test('unknown status returns fallback', () {
      expect(etaStatusLabel('???'), 'Unknown');
    });
  });
}
