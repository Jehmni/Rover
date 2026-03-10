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
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants.dart';
import '../services/auth_service.dart';
import '../services/org_service.dart';
import '../widgets/auth_dialog.dart';
import 'admin_home_page.dart';
import 'driver_home_page.dart';
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
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(
          height: double.infinity,
          width: double.infinity,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Organisation Setup',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'OpenSans',
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _logout,
                        child: const Text(
                          'Sign Out',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 6, 24, 0),
                  child: Text(
                    'Link your account to your organisation to continue.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'OpenSans',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Tabs ────────────────────────────────────────────
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    labelColor: const Color(0xFF478DE0),
                    unselectedLabelColor: Colors.white,
                    labelStyle: const TextStyle(
                      fontFamily: 'OpenSans',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: const [
                      Tab(text: 'Create Organisation'),
                      Tab(text: 'Join Organisation'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You will become the admin for this organisation.',
            style: TextStyle(
              color: Colors.white70,
              fontFamily: 'OpenSans',
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          _field(
            controller: _nameCtrl,
            label: 'Organisation Name *',
            hint: "e.g. St. Mary's Church",
            icon: Icons.business,
          ),
          _field(
            controller: _cityCtrl,
            label: 'City (optional)',
            hint: 'e.g. Manchester',
            icon: Icons.location_city,
          ),
          _field(
            controller: _countryCtrl,
            label: 'Country (optional)',
            hint: 'e.g. United Kingdom',
            icon: Icons.flag,
          ),
          Text('Organisation Type', style: kLabelStyle),
          const SizedBox(height: 10),
          Container(
            decoration: kBoxDecorationStyle,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _orgType,
                dropdownColor: const Color(0xFF478DE0),
                isExpanded: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'OpenSans',
                  fontSize: 16,
                ),
                items: _orgTypes
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t[0].toUpperCase() + t.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _orgType = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleCreate,
              style: ElevatedButton.styleFrom(
                elevation: 5,
                padding: const EdgeInsets.all(15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Color(0xFF527DAA))
                  : const Text(
                      'CREATE ORGANISATION',
                      style: TextStyle(
                        color: Color(0xFF527DAA),
                        letterSpacing: 1.5,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'OpenSans',
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: kLabelStyle),
        const SizedBox(height: 10),
        Container(
          alignment: Alignment.centerLeft,
          decoration: kBoxDecorationStyle,
          height: 60,
          child: TextField(
            controller: controller,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'OpenSans'),
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: const EdgeInsets.only(top: 14),
              prefixIcon: Icon(icon, color: Colors.white),
              hintText: hint,
              hintStyle: kHintTextStyle,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Org banner from deep link ────────────────────────
          if (widget.orgName != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Joining: ${widget.orgName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'OpenSans',
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const Text(
              'Your administrator will share an invite link or QR code '
              'with you. Scan it or paste the link below.',
              style: TextStyle(
                color: Colors.white70,
                fontFamily: 'OpenSans',
                fontSize: 12,
                height: 1.5,
              ),
            ),

          const SizedBox(height: 20),

          // ── QR scan button ───────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startScanning,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF478DE0),
                padding: const EdgeInsets.all(15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 3,
              ),
              icon: const Icon(Icons.qr_code_scanner, size: 22),
              label: const Text(
                'SCAN QR CODE',
                style: TextStyle(
                  fontFamily: 'OpenSans',
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 16,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
          Row(
            children: const [
              Expanded(
                  child:
                      Divider(color: Colors.white54, thickness: 0.8)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR PASTE LINK',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Expanded(
                  child:
                      Divider(color: Colors.white54, thickness: 0.8)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Token / URL text field ───────────────────────────
          Text('Invite Link', style: kLabelStyle),
          const SizedBox(height: 10),
          Container(
            alignment: Alignment.centerLeft,
            decoration: kBoxDecorationStyle,
            child: TextField(
              controller: _tokenCtrl,
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'OpenSans'),
              onSubmitted: (_) => _handleJoin(),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                prefixIcon:
                    Icon(Icons.link, color: Colors.white),
                hintText: 'rover.app/join/…',
                hintStyle: TextStyle(
                  color: Colors.white38,
                  fontFamily: 'OpenSans',
                  fontSize: 14,
                ),
              ),
            ),
          ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleJoin,
              style: ElevatedButton.styleFrom(
                elevation: 5,
                padding: const EdgeInsets.all(15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(
                      color: Color(0xFF527DAA))
                  : const Text(
                      'JOIN ORGANISATION',
                      style: TextStyle(
                        color: Color(0xFF527DAA),
                        letterSpacing: 1.5,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'OpenSans',
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Search fallback — deprioritised small text link ──
          Center(
            child: TextButton(
              onPressed: () => _showSearchDialog(context, widget.role),
              child: const Text(
                "Can't find your link? Search for your organisation",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontFamily: 'OpenSans',
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white60,
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
  String? _sentToOrgId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await OrgService.searchOrgs(q);
      if (mounted) setState(() => _results = results);
    } catch (_) {
      if (mounted) setState(() => _results = []);
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
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Search Organisations'),
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
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 12),
            if (_isSearching)
              const Center(child: CircularProgressIndicator())
            else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
              const Text('No results. Try a different name or city.',
                  style: TextStyle(color: Colors.grey, fontSize: 13))
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
                      title: Text(name),
                      subtitle: city != null ? Text(city) : null,
                      trailing: sent
                          ? const Icon(Icons.check_circle,
                              color: Colors.green)
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
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green),
                ),
                child: const Text(
                  'Request sent. Your administrator will be notified '
                  'and can approve you from the Share tab.',
                  style: TextStyle(fontSize: 12, color: Colors.green),
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
                fontFamily: 'OpenSans',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
