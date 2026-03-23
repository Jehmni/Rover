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
import 'package:google_fonts/google_fonts.dart';
import '../services/org_service.dart';
import '../theme/rover_theme.dart';
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
      backgroundColor: RoverColors.surface,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Back button row
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  color: RoverColors.textSecondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Heading
                      Text(
                        'Join Rover',
                        style: GoogleFonts.inter(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: RoverColors.primary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'How will you be using Rover?',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: RoverColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Org invite banner — visible when arriving via deep link
                      if (widget.orgToken != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: RoverColors.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.link,
                                  color: RoverColors.primary, size: 18),
                              const SizedBox(width: 10),
                              if (_loadingOrg)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              else
                                Expanded(
                                  child: Text(
                                    _resolvedOrgName != null
                                        ? 'Joining: $_resolvedOrgName'
                                        : 'Invite link detected',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: RoverColors.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      const SizedBox(height: 8),

                      // Role cards
                      _RoleCard(
                        icon: Icons.admin_panel_settings_rounded,
                        title: "I'm organising events",
                        subtitle:
                            'Create events, assign drivers and manage '
                            'your organisation.',
                        onTap: () => _selectRole('admin'),
                      ),
                      const SizedBox(height: 14),
                      _RoleCard(
                        icon: Icons.directions_bus_rounded,
                        title: "I'm a driver",
                        subtitle:
                            'See your assigned pickups and navigate '
                            'to event venues.',
                        onTap: () => _selectRole('driver'),
                      ),
                      const SizedBox(height: 14),
                      _RoleCard(
                        icon: Icons.people_rounded,
                        title: "I'm attending an event",
                        subtitle:
                            'Find events near you and register for pickup.',
                        onTap: () => _selectRole('user'),
                      ),
                      const SizedBox(height: 32),

                      // Sign in link
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Already have an account? Sign in',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: RoverColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single role-selection card — amber left accent border design
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
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border(
              left: BorderSide(color: RoverColors.secondary, width: 4),
            ),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: RoverColors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: RoverColors.secondary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: RoverColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: RoverColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: RoverColors.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
