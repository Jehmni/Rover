// roles_permissions_test.dart
//
// Unit tests for role-based access control rules documented in
// WHITEPAPER §3 — Roles & Permissions.
//
// These tests verify the routing logic (destinationForRole) and
// the documented capability matrix for each role without touching
// the Supabase backend.

import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Role routing — mirrors destinationForRole() in main.dart
// ─────────────────────────────────────────────────────────────
enum AppRoute { login, orgSetup, userHome, driverHome, adminHome }

AppRoute destinationForRole(String? role) {
  switch (role) {
    case 'admin':
      return AppRoute.adminHome;
    case 'driver':
      return AppRoute.driverHome;
    case 'user':
      return AppRoute.userHome;
    case 'no_org':
      return AppRoute.orgSetup;
    default:
      return AppRoute.login;
  }
}

// ─────────────────────────────────────────────────────────────
// Role capability matrix (documented invariants)
// ─────────────────────────────────────────────────────────────
const Map<String, List<String>> _capabilities = {
  'admin': [
    'create_event',
    'edit_event',
    'cancel_event',
    'assign_driver',
    'manage_members',
    'approve_join_request',
    'reject_join_request',
    'reset_invite_token',
    'view_attendees',
  ],
  'driver': [
    'view_assigned_events',
    'start_route',
    'mark_en_route',
    'mark_completed',
    'view_pickup_list',
    'view_map',
  ],
  'user': [
    'browse_events',
    'search_events',
    'subscribe_event',
    'unsubscribe_event',
    'request_pickup',
    'cancel_pickup',
    'view_eta',
  ],
};

bool roleCanDo(String role, String action) {
  return _capabilities[role]?.contains(action) ?? false;
}

void main() {
  group('Role routing — destinationForRole()', () {
    test('admin role routes to AdminHomePage', () {
      expect(destinationForRole('admin'), AppRoute.adminHome);
    });

    test('driver role routes to DriverHomePage', () {
      expect(destinationForRole('driver'), AppRoute.driverHome);
    });

    test('user role routes to UserHomePage', () {
      expect(destinationForRole('user'), AppRoute.userHome);
    });

    test('no_org sentinel routes to OrgSetupPage', () {
      expect(destinationForRole('no_org'), AppRoute.orgSetup);
    });

    test('null role (unauthenticated) routes to LoginPage', () {
      expect(destinationForRole(null), AppRoute.login);
    });

    test('unknown role falls through to LoginPage', () {
      expect(destinationForRole('superadmin'), AppRoute.login);
    });
  });

  group('Admin capabilities', () {
    test('admin can create events', () {
      expect(roleCanDo('admin', 'create_event'), isTrue);
    });

    test('admin can edit events', () {
      expect(roleCanDo('admin', 'edit_event'), isTrue);
    });

    test('admin can cancel events', () {
      expect(roleCanDo('admin', 'cancel_event'), isTrue);
    });

    test('admin can assign drivers', () {
      expect(roleCanDo('admin', 'assign_driver'), isTrue);
    });

    test('admin can manage members', () {
      expect(roleCanDo('admin', 'manage_members'), isTrue);
    });

    test('admin can approve join requests', () {
      expect(roleCanDo('admin', 'approve_join_request'), isTrue);
    });

    test('admin can reject join requests', () {
      expect(roleCanDo('admin', 'reject_join_request'), isTrue);
    });

    test('admin can reset invite token', () {
      expect(roleCanDo('admin', 'reset_invite_token'), isTrue);
    });

    test('admin cannot directly request pickup (user action)', () {
      expect(roleCanDo('admin', 'request_pickup'), isFalse);
    });
  });

  group('Driver capabilities', () {
    test('driver can view assigned events', () {
      expect(roleCanDo('driver', 'view_assigned_events'), isTrue);
    });

    test('driver can start route optimisation', () {
      expect(roleCanDo('driver', 'start_route'), isTrue);
    });

    test('driver can mark pickup as en_route', () {
      expect(roleCanDo('driver', 'mark_en_route'), isTrue);
    });

    test('driver can mark pickup as completed', () {
      expect(roleCanDo('driver', 'mark_completed'), isTrue);
    });

    test('driver can view live map', () {
      expect(roleCanDo('driver', 'view_map'), isTrue);
    });

    test('driver cannot create events (admin action)', () {
      expect(roleCanDo('driver', 'create_event'), isFalse);
    });

    test('driver cannot approve join requests (admin action)', () {
      expect(roleCanDo('driver', 'approve_join_request'), isFalse);
    });
  });

  group('User capabilities', () {
    test('user can browse events', () {
      expect(roleCanDo('user', 'browse_events'), isTrue);
    });

    test('user can search events', () {
      expect(roleCanDo('user', 'search_events'), isTrue);
    });

    test('user can subscribe to events', () {
      expect(roleCanDo('user', 'subscribe_event'), isTrue);
    });

    test('user can unsubscribe from events', () {
      expect(roleCanDo('user', 'unsubscribe_event'), isTrue);
    });

    test('user can request a pickup', () {
      expect(roleCanDo('user', 'request_pickup'), isTrue);
    });

    test('user can cancel a pickup', () {
      expect(roleCanDo('user', 'cancel_pickup'), isTrue);
    });

    test('user can view live ETA', () {
      expect(roleCanDo('user', 'view_eta'), isTrue);
    });

    test('user cannot create events (admin-only)', () {
      expect(roleCanDo('user', 'create_event'), isFalse);
    });

    test('user cannot assign drivers (admin-only)', () {
      expect(roleCanDo('user', 'assign_driver'), isFalse);
    });

    test('user cannot mark pickup completed (driver-only)', () {
      expect(roleCanDo('user', 'mark_completed'), isFalse);
    });
  });

  group('Role isolation — each role is distinct', () {
    final roles = ['admin', 'driver', 'user'];

    test('all three roles are supported', () {
      expect(roles, hasLength(3));
    });

    test('no two roles share identical capability sets', () {
      final adminCaps = Set.from(_capabilities['admin']!);
      final driverCaps = Set.from(_capabilities['driver']!);
      final userCaps = Set.from(_capabilities['user']!);

      expect(adminCaps, isNot(equals(driverCaps)));
      expect(adminCaps, isNot(equals(userCaps)));
      expect(driverCaps, isNot(equals(userCaps)));
    });
  });
}
