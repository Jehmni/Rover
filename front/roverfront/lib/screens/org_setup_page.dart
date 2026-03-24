// org_setup_page.dart
//
// Shown when an authenticated user's profile has no org_id.
// This happens in two scenarios:
//   1. New user just registered and needs to create or join an org.
//   2. User confirmed email in a browser and returned to the app.
//
// Two tabs:
//   Tab A — Create Organisation  → becomes admin of a new org.
//   Tab B — Join Organisation    → scans QR / enters token to join.
//
// Constructor params:
//   initialRole — 'admin' | 'driver' | 'user'  (from WelcomePage card)
//                 admin → start on Tab A, others → start on Tab B
//   orgToken    — UUID from deep link; pre-fills the token field on Tab B
//   orgName     — display name shown in the banner

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/auth_service.dart';
import '../services/org_service.dart';
import '../theme/rover_theme.dart';
import '../widgets/auth_dialog.dart';
import 'admin_home_page.dart';
import 'driver_home_page.dart';
import 'user_guide_page.dart';
import 'user_home_page.dart';

class OrgSetupPage extends StatefulWidget {
  const OrgSetupPage({
    super.key,
    this.initialRole = 'user',
    this.orgToken,
    this.orgName,
  });

  final String  initialRole;
  final String? orgToken;
  final String? orgName;

  @override
  State<OrgSetupPage> createState() => _OrgSetupPageState();
}

class _OrgSetupPageState extends State<OrgSetupPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Admins start on Tab A (Create); drivers and users start on Tab B (Join).
    final initialIndex = widget.initialRole == 'admin' ? 0 : 1;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
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
              // ── Header ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rover',
                            style: GoogleFonts.inter(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: RoverColors.primary,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Link your account to get started.',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: RoverColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.help_outline),
                      color: RoverColors.textSecondary,
                      tooltip: 'Help',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const UserGuidePage(),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _logout,
                      child: Text(
                        'Sign Out',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: RoverColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Tabs ────────────────────────────────────────────
              TabBar(
                controller: _tabController,
                indicatorColor: RoverColors.primary,
                indicatorWeight: 2,
                labelColor: RoverColors.primary,
                unselectedLabelColor: RoverColors.textSecondary,
                labelStyle: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w700),
                unselectedLabelStyle:
                    GoogleFonts.inter(fontSize: 13),
                tabs: const [
                  Tab(text: 'Create Organisation'),
                  Tab(text: 'Join Organisation'),
                ],
              ),
              const Divider(height: 1),

              // ── Tab Views ────────────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    const _CreateOrgTab(),
                    _JoinOrgTab(
                      initialToken: widget.orgToken,
                      orgName:      widget.orgName,
                      role:         widget.initialRole == 'admin'
                                        ? 'user'
                                        : widget.initialRole,
                    ),
                  ],
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
// TAB A — CREATE ORGANISATION
// ─────────────────────────────────────────────────────────────────────────────
class _CreateOrgTab extends StatefulWidget {
  const _CreateOrgTab();

  @override
  State<_CreateOrgTab> createState() => _CreateOrgTabState();
}

class _CreateOrgTabState extends State<_CreateOrgTab> {
  final _nameCtrl    = TextEditingController();
  final _cityCtrl    = TextEditingController();
  final _countryCtrl = TextEditingController();
  String _orgType    = 'church';
  bool   _isLoading  = false;

  static const _orgTypes = [
    'church', 'conference', 'corporate', 'school', 'other',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _countryCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleCreate() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showErrorDialog(context, 'Organisation name is required.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await OrgService.createOrganisationAndAdmin(
        orgName: _nameCtrl.text.trim(),
        city:    _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        country: _countryCtrl.text.trim().isEmpty
                     ? null
                     : _countryCtrl.text.trim(),
        orgType: _orgType,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminHomePage()),
      );
    } catch (e) {
      if (mounted) {
        showErrorDialog(
            context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You will become the admin for this organisation.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: RoverColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          _label('Organisation Name *'),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            style: GoogleFonts.inter(
                fontSize: 15, color: RoverColors.textPrimary),
            decoration: InputDecoration(
              hintText: "e.g. St. Mary's Church",
              prefixIcon: const Icon(Icons.business_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _label('City (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _cityCtrl,
            style: GoogleFonts.inter(
                fontSize: 15, color: RoverColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. Manchester',
              prefixIcon: const Icon(Icons.location_city_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _label('Country (optional)'),
          const SizedBox(height: 6),
          TextField(
            controller: _countryCtrl,
            style: GoogleFonts.inter(
                fontSize: 15, color: RoverColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'e.g. United Kingdom',
              prefixIcon: const Icon(Icons.flag_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _label('Organisation Type'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _orgType,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.category_outlined, size: 20),
            ),
            items: _orgTypes
                .map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(
                        t[0].toUpperCase() + t.substring(1),
                        style: GoogleFonts.inter(
                            fontSize: 15, color: RoverColors.textPrimary),
                      ),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _orgType = v);
            },
          ),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleCreate,
              style: FilledButton.styleFrom(
                backgroundColor: RoverColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Create Organisation',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: RoverColors.textSecondary,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB B — JOIN ORGANISATION (token / QR based)
// ─────────────────────────────────────────────────────────────────────────────
class _JoinOrgTab extends StatefulWidget {
  const _JoinOrgTab({
    this.initialToken,
    this.orgName,
    this.role = 'user',
  });

  final String? initialToken;
  final String? orgName;
  final String  role;  // 'user' | 'driver'

  @override
  State<_JoinOrgTab> createState() => _JoinOrgTabState();
}

class _JoinOrgTabState extends State<_JoinOrgTab> {
  late final TextEditingController _tokenCtrl;
  bool _isLoading  = false;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _tokenCtrl = TextEditingController(text: widget.initialToken ?? '');
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    final raw = _tokenCtrl.text.trim();
    if (raw.isEmpty) {
      showErrorDialog(context,
          'Please enter or scan the invite link from your administrator.');
      return;
    }

    // Accept either a full URL (rover.app/join/TOKEN) or a bare UUID
    String token = raw;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.pathSegments.length >= 2) {
      final joinIdx = uri.pathSegments.indexOf('join');
      if (joinIdx >= 0 && joinIdx + 1 < uri.pathSegments.length) {
        token = uri.pathSegments[joinIdx + 1];
      }
    }

    // Validate the resolved token is UUID-shaped before hitting the RPC.
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    if (!uuidPattern.hasMatch(token)) {
      showErrorDialog(
        context,
        "That doesn't look like a Rover invite code. "
        'Ask your administrator to share the link again.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final role = await OrgService.joinOrganisation(
        token: token,
        role:  widget.role,
      );
      if (!mounted) return;

      Widget destination;
      switch (role) {
        case 'driver':
          destination = const DriverHomePage();
          break;
        case 'admin':
          destination = const AdminHomePage();
          break;
        default:
          destination = const UserHomePage();
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => destination),
      );
    } catch (e) {
      if (mounted) {
        showErrorDialog(
            context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startScanning() {
    setState(() => _isScanning = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return _QrScanOverlay(
        onDetected: (value) {
          setState(() {
            _isScanning = false;
            _tokenCtrl.text = value;
          });
          // Auto-join after scan
          _handleJoin();
        },
        onCancel: () => setState(() => _isScanning = false),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Org banner from deep link
          if (widget.orgName != null) ...[
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
                  Icon(Icons.business, color: RoverColors.primary, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Joining: ${widget.orgName}',
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
            const SizedBox(height: 20),
          ] else ...[
            Text(
              'Your administrator will share an invite link or QR code with you. '
              'Scan it or paste the link below.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: RoverColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
          ],

          // QR scan button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _startScanning,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: RoverColors.primary, width: 1.5),
                foregroundColor: RoverColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: Text(
                'Scan QR Code',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Divider
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'or paste link',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: RoverColors.textSecondary),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 20),

          // Token / URL text field
          Text(
            'Invite Link',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: RoverColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tokenCtrl,
            style: GoogleFonts.inter(
                fontSize: 15, color: RoverColors.textPrimary),
            onSubmitted: (_) => _handleJoin(),
            decoration: InputDecoration(
              hintText: 'rover.app/join/…',
              prefixIcon: const Icon(Icons.link, size: 20),
            ),
          ),
          const SizedBox(height: 28),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isLoading ? null : _handleJoin,
              style: FilledButton.styleFrom(
                backgroundColor: RoverColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Join Organisation',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Search fallback
          Center(
            child: TextButton(
              onPressed: () => _showSearchDialog(context, widget.role),
              child: Text(
                "Can't find your link? Search for your organisation",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: RoverColors.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: RoverColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search fallback dialog ──────────────────────────────────
  static void _showSearchDialog(BuildContext context, String role) {
    showDialog(
      context: context,
      builder: (_) => _OrgSearchDialog(role: role),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Org Search Dialog — search fallback (deprioritised path)
// ─────────────────────────────────────────────────────────────────────────────
class _OrgSearchDialog extends StatefulWidget {
  const _OrgSearchDialog({required this.role});
  final String role;

  @override
  State<_OrgSearchDialog> createState() => _OrgSearchDialogState();
}

class _OrgSearchDialogState extends State<_OrgSearchDialog> {
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _isSearching  = false;
  bool _isRequesting = false;
  bool _searchError  = false;
  String? _sentToOrgId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() { _results = []; _searchError = false; });
      return;
    }
    setState(() { _isSearching = true; _searchError = false; });
    try {
      final results = await OrgService.searchOrgs(q);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() { _results = []; _searchError = true; });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _requestToJoin(String orgId) async {
    setState(() => _isRequesting = true);
    try {
      await OrgService.requestToJoin(orgId);
      if (mounted) setState(() => _sentToOrgId = orgId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: RoverColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Search Organisations',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Name or city…',
                isDense: true,
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 12),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else if (_searchError)
              Text(
                'Search failed — check your connection and try again.',
                style: GoogleFonts.inter(color: RoverColors.error, fontSize: 13),
              )
            else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
              Text('No results. Try a different name or city.',
                  style: GoogleFonts.inter(
                      color: RoverColors.textSecondary, fontSize: 13))
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final org    = _results[i];
                    final id     = org['id']   as String;
                    final name   = org['name'] as String? ?? 'Unknown';
                    final city   = org['city'] as String?;
                    final sent   = _sentToOrgId == id;

                    return ListTile(
                      dense: true,
                      title: Text(name,
                          style: GoogleFonts.inter(fontSize: 14)),
                      subtitle: city != null
                          ? Text(city,
                              style: GoogleFonts.inter(fontSize: 12))
                          : null,
                      trailing: sent
                          ? Icon(Icons.check_circle,
                              color: RoverColors.primary)
                          : TextButton(
                              onPressed: _isRequesting
                                  ? null
                                  : () => _requestToJoin(id),
                              child: const Text('Request'),
                            ),
                    );
                  },
                ),
              ),
            if (_sentToOrgId != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: RoverColors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Request sent. Your administrator will be notified '
                  'and can approve you from the Share tab.',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: RoverColors.primary),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: const Text('Close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR Scan Overlay
// ─────────────────────────────────────────────────────────────────────────────
class _QrScanOverlay extends StatefulWidget {
  const _QrScanOverlay({
    required this.onDetected,
    required this.onCancel,
  });

  final void Function(String value) onDetected;
  final VoidCallback onCancel;

  @override
  State<_QrScanOverlay> createState() => _QrScanOverlayState();
}

class _QrScanOverlayState extends State<_QrScanOverlay> {
  bool _detected = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            if (_detected) return;
            final barcode = capture.barcodes.firstOrNull;
            final value = barcode?.rawValue;
            if (value != null && value.isNotEmpty) {
              _detected = true;
              widget.onDetected(value);
            }
          },
        ),
        // Cancel button overlay
        Positioned(
          top: 40,
          left: 16,
          child: SafeArea(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Cancel'),
              onPressed: widget.onCancel,
            ),
          ),
        ),
        // Scan hint
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: 80),
            child: Text(
              'Point camera at the QR code',
              style: TextStyle(
                color: Colors.white,
                backgroundColor: Colors.black45,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
