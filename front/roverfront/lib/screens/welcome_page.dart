// welcome_page.dart
//
// Entry point for new users. Three plain-language cards guide the user
// to the correct registration flow without ever showing the word "role".
//
// Optional orgToken + orgName params are supplied when the user arrives
// via a deep link (rover.app/join/TOKEN). The token is passed through
// registration to OrgSetupPage so the join step is pre-filled.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/org_service.dart';
import 'register_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    this.orgToken,
    this.orgName,
  });

  /// UUID token from a rover.app/join/TOKEN deep link (may be null).
  final String? orgToken;

  /// Pre-resolved org name (avoids a second RPC when already known).
  final String? orgName;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  String? _resolvedOrgName;
  bool _loadingOrg = false;

  @override
  void initState() {
    super.initState();
    if (widget.orgToken != null && widget.orgName == null) {
      _resolveOrgName(widget.orgToken!);
    } else {
      _resolvedOrgName = widget.orgName;
    }
  }

  Future<void> _resolveOrgName(String token) async {
    setState(() => _loadingOrg = true);
    try {
      final org = await OrgService.getOrgFromToken(token);
      if (mounted && org != null) {
        setState(() => _resolvedOrgName = org['name'] as String?);
      }
    } catch (_) {
      // Token may be invalid — let the join step surface the error.
    } finally {
      if (mounted) setState(() => _loadingOrg = false);
    }
  }

  void _selectRole(String role) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RegisterPage(
        role: role,
        orgToken: widget.orgToken,
        orgName: _resolvedOrgName,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF73AEF5),
                Color(0xFF61A4F1),
                Color(0xFF478DE0),
                Color(0xFF398AE5),
              ],
              stops: [0.1, 0.4, 0.7, 0.9],
            ),
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 32),
                const Icon(Icons.directions_bus_rounded,
                    size: 60, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'Welcome to Rover',
                  style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'OpenSans',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // ── Org banner — visible when arriving via deep link ──
                if (widget.orgToken != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link,
                              color: Colors.white70, size: 16),
                          const SizedBox(width: 8),
                          if (_loadingOrg)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white70),
                            )
                          else
                            Expanded(
                              child: Text(
                                _resolvedOrgName != null
                                    ? 'Joining: $_resolvedOrgName'
                                    : 'Invite link detected',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontFamily: 'OpenSans',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 12),
                const Text(
                  'How will you be using Rover?',
                  style: TextStyle(
                    color: Colors.white70,
                    fontFamily: 'OpenSans',
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Role cards ────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                    child: Column(
                      children: [
                        _RoleCard(
                          icon: Icons.admin_panel_settings_rounded,
                          title: "I'm organising events",
                          subtitle:
                              'Create events, assign drivers and manage '
                              'your organisation.',
                          onTap: () => _selectRole('admin'),
                        ),
                        const SizedBox(height: 16),
                        _RoleCard(
                          icon: Icons.directions_bus_rounded,
                          title: "I'm a driver",
                          subtitle:
                              'See your assigned pickups and navigate '
                              'to event venues.',
                          onTap: () => _selectRole('driver'),
                        ),
                        const SizedBox(height: 16),
                        _RoleCard(
                          icon: Icons.people_rounded,
                          title: "I'm attending an event",
                          subtitle:
                              'Find events near you and register '
                              'for pickup.',
                          onTap: () => _selectRole('user'),
                        ),
                        const SizedBox(height: 28),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(
                            'Already have an account? Sign in',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white70,
                              fontFamily: 'OpenSans',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single role-selection card
// ─────────────────────────────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F2FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(icon, color: const Color(0xFF478DE0), size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'OpenSans',
                        color: Color(0xFF2D3748),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontFamily: 'OpenSans',
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
