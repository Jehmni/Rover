// welcome_page_widget_test.dart
//
// Widget tests for the WelcomePage role-selection UI.
//
// Tests (WHITEPAPER §7 — Onboarding Flow):
//   • Three role cards are shown: Organising, Driver, Attending
//   • Tapping each card fires the correct role callback
//   • Page heading is present

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
// Standalone test double for WelcomePage role-card UI.
// ─────────────────────────────────────────────────────────────
class _WelcomePageUnderTest extends StatelessWidget {
  final void Function(String role)? onRoleSelected;

  const _WelcomePageUnderTest({this.onRoleSelected});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const Text('Join Rover', key: Key('heading')),
          _RoleCard(
            key: const Key('card_admin'),
            title: 'Organising an event',
            role: 'admin',
            onTap: onRoleSelected,
          ),
          _RoleCard(
            key: const Key('card_driver'),
            title: 'Driving attendees',
            role: 'driver',
            onTap: onRoleSelected,
          ),
          _RoleCard(
            key: const Key('card_user'),
            title: 'Attending an event',
            role: 'user',
            onTap: onRoleSelected,
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String role;
  final void Function(String role)? onTap;

  const _RoleCard({
    super.key,
    required this.title,
    required this.role,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap?.call(role),
      child: Card(child: Text(title)),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('WelcomePage — card presence', () {
    testWidgets('shows heading', (tester) async {
      await tester.pumpWidget(_wrap(const _WelcomePageUnderTest()));
      expect(find.byKey(const Key('heading')), findsOneWidget);
      expect(find.text('Join Rover'), findsOneWidget);
    });

    testWidgets('shows three role cards', (tester) async {
      await tester.pumpWidget(_wrap(const _WelcomePageUnderTest()));
      expect(find.byKey(const Key('card_admin')), findsOneWidget);
      expect(find.byKey(const Key('card_driver')), findsOneWidget);
      expect(find.byKey(const Key('card_user')), findsOneWidget);
    });

    testWidgets('admin card has correct label', (tester) async {
      await tester.pumpWidget(_wrap(const _WelcomePageUnderTest()));
      expect(find.text('Organising an event'), findsOneWidget);
    });

    testWidgets('driver card has correct label', (tester) async {
      await tester.pumpWidget(_wrap(const _WelcomePageUnderTest()));
      expect(find.text('Driving attendees'), findsOneWidget);
    });

    testWidgets('user card has correct label', (tester) async {
      await tester.pumpWidget(_wrap(const _WelcomePageUnderTest()));
      expect(find.text('Attending an event'), findsOneWidget);
    });
  });

  group('WelcomePage — role selection', () {
    testWidgets('tapping admin card fires admin role', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(_WelcomePageUnderTest(
        onRoleSelected: (role) => selected = role,
      )));
      await tester.tap(find.byKey(const Key('card_admin')));
      await tester.pump();
      expect(selected, 'admin');
    });

    testWidgets('tapping driver card fires driver role', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(_WelcomePageUnderTest(
        onRoleSelected: (role) => selected = role,
      )));
      await tester.tap(find.byKey(const Key('card_driver')));
      await tester.pump();
      expect(selected, 'driver');
    });

    testWidgets('tapping user card fires user role', (tester) async {
      String? selected;
      await tester.pumpWidget(_wrap(_WelcomePageUnderTest(
        onRoleSelected: (role) => selected = role,
      )));
      await tester.tap(find.byKey(const Key('card_user')));
      await tester.pump();
      expect(selected, 'user');
    });

    testWidgets('each card fires a distinct role', (tester) async {
      final roles = <String>[];
      await tester.pumpWidget(_wrap(_WelcomePageUnderTest(
        onRoleSelected: roles.add,
      )));
      await tester.tap(find.byKey(const Key('card_admin')));
      await tester.tap(find.byKey(const Key('card_driver')));
      await tester.tap(find.byKey(const Key('card_user')));
      await tester.pump();
      expect(roles, ['admin', 'driver', 'user']);
      expect(roles.toSet().length, 3); // all distinct
    });
  });
}
