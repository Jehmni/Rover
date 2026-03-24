// driver_home_page.dart
//
// Fixes applied in this revision:
//   M-3 — Profiles cache: getPickupProfiles() pre-fetches userId→profile map
//          so names/phones are available in the realtime stream (which cannot
//          use PostgREST joins).
//   M-4 — _pickupOrder and _profilesCache are cleared when _activeEventId
//          changes so stale data from a previous event is never shown.
//   L-2 — en_route button added: driver can mark a pickup as en_route
//          before tapping Done (completed). Full status progression:
//          pending → en_route → completed.
//   NEW — "View Map" FAB opens DriverMapPage with the live pickup list.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/pickup_service.dart';
import '../theme/rover_theme.dart';
import 'driver_map_page.dart';
import 'user_guide_page.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  List<Map<String, dynamic>> _assignedEvents = [];
  bool _isLoading    = true;
  bool _isScheduling = false;

  // Active route state
  int?    _activeEventId;
  String? _activeEventName;

  // Fix M-3: profiles map cross-referenced against stream rows
  Map<String, Map<String, dynamic>> _profilesCache = {};

  // Fix M-4: cleared whenever _activeEventId changes
  List<Map<String, dynamic>> _pickupOrder = [];

  @override
  void initState() {
    super.initState();
    _loadAssignedEvents();
  }

  Future<void> _loadAssignedEvents() async {
    setState(() => _isLoading = true);
    try {
      final events = await EventService.getDriverEvents();
      setState(() => _assignedEvents = events);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _startRoute(int eventId, String eventName) async {
    // Fix M-4: reset all active-route state before switching events
    setState(() {
      _isScheduling   = true;
      _activeEventId  = eventId;
      _activeEventName = eventName;
      _pickupOrder    = [];
      _profilesCache  = {};
    });
    try {
      final ordered = await PickupService.scheduleRoute(eventId);

      // Fix M-3: pre-fetch profiles so the stream can resolve names/phones
      final profiles = await PickupService.getPickupProfiles(eventId);

      setState(() {
        _pickupOrder   = ordered;
        _profilesCache = profiles;
      });
      _showSnack(
          'Route optimised — ${ordered.length} pickup(s) scheduled.',
          RoverColors.primary);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isScheduling = false);
    }
  }

  Future<void> _markEnRoute(int pickupId) async {
    try {
      await PickupService.markEnRoute(pickupId);
      _showSnack('Status updated — en route.', RoverColors.secondary);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _markCompleted(int pickupId) async {
    try {
      await PickupService.markCompleted(pickupId);
      _showSnack('Pickup marked as completed.', RoverColors.primary);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _logout() async {
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/');
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: RoverColors.error),
    );
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoverColors.surface,
      floatingActionButton: _activeEventId != null
          ? FloatingActionButton.extended(
              backgroundColor: RoverColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.map),
              label: Text('View Map',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverMapPage(
                    eventId:       _activeEventId!,
                    eventName:     _activeEventName ?? 'Route',
                    profilesCache: _profilesCache,
                  ),
                ),
              ),
            )
          : null,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: RoverColors.primary,
            foregroundColor: Colors.white,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 0, 16),
              title: Text(
                'Driver Dashboard',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              background: Container(color: RoverColors.primary),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'Help',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UserGuidePage(role: 'driver'),
                  ),
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.logout), onPressed: _logout),
            ],
          ),

          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            // ── Assigned events ───────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Text(
                  'Assigned Events',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: RoverColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),

            if (_assignedEvents.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No events assigned to you yet.',
                      style: GoogleFonts.inter(
                          color: RoverColors.textSecondary, fontSize: 15),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final event = _assignedEvents[index];
                      final eventDate = event['event_date'] != null
                          ? DateTime.tryParse(event['event_date'] as String)
                          : null;
                      final isActive =
                          _activeEventId == event['id'] as int;

                      return _EventRouteCard(
                        name: event['name'] as String? ?? 'Unnamed',
                        eventDate: eventDate,
                        isActive: isActive,
                        isScheduling: _isScheduling &&
                            _activeEventId == event['id'] as int,
                        onStart: _isScheduling
                            ? null
                            : () => _startRoute(
                                  event['id'] as int,
                                  event['name'] as String? ?? 'Event',
                                ),
                      );
                    },
                    childCount: _assignedEvents.length,
                  ),
                ),
              ),

            // ── Live pickup order ─────────────────────────
            if (_activeEventId != null) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Pickup Order — $_activeEventName',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: RoverColors.textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Text(
                        '${_pickupOrder.where((p) => p['status'] != 'completed').length} remaining',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: RoverColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: PickupService.listenToPickupUpdates(
                      _activeEventId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                            ConnectionState.waiting &&
                        _pickupOrder.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    final pickups =
                        snapshot.hasData && snapshot.data!.isNotEmpty
                            ? snapshot.data!
                            : _pickupOrder;

                    if (pickups.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'No pickup requests yet.',
                            style: GoogleFonts.inter(
                                color: RoverColors.textSecondary),
                          ),
                        ),
                      );
                    }

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      child: Column(
                        children: pickups.map((p) {
                          final order  = p['pickup_order'];
                          final eta    = p['eta_minutes'];
                          final status =
                              p['status'] as String? ?? 'pending';
                          final userId =
                              p['user_id'] as String? ?? '';
                          final profile = _profilesCache[userId];
                          final userName = profile?['full_name']
                                  as String? ??
                              'Passenger';
                          final phone =
                              profile?['phone'] as String?;

                          return _PickupCard(
                            order: order,
                            userName: userName,
                            phone: phone,
                            eta: eta,
                            status: status,
                            onEnRoute: () =>
                                _markEnRoute(p['id'] as int),
                            onDone: () =>
                                _markCompleted(p['id'] as int),
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Event route card — shows event info and Start/Re-route button
// ─────────────────────────────────────────────────────────────────────────────
class _EventRouteCard extends StatelessWidget {
  const _EventRouteCard({
    required this.name,
    required this.eventDate,
    required this.isActive,
    required this.isScheduling,
    required this.onStart,
  });

  final String name;
  final DateTime? eventDate;
  final bool isActive;
  final bool isScheduling;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isActive ? RoverColors.primaryContainer : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isActive
            ? Border.all(
                color: RoverColors.primary.withValues(alpha: 0.3),
                width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: RoverColors.textPrimary,
                    ),
                  ),
                  if (eventDate != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${eventDate!.day}/${eventDate!.month}/${eventDate!.year}  '
                      '${eventDate!.hour.toString().padLeft(2, '0')}:'
                      '${eventDate!.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: RoverColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onStart,
              icon: isScheduling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Icon(
                      isActive ? Icons.refresh : Icons.play_arrow,
                      size: 16),
              label: Text(
                isActive ? 'Re-route' : 'Start Route',
                style: GoogleFonts.inter(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: isActive
                    ? RoverColors.secondary
                    : RoverColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pickup list card
// ─────────────────────────────────────────────────────────────────────────────
class _PickupCard extends StatelessWidget {
  const _PickupCard({
    required this.order,
    required this.userName,
    required this.phone,
    required this.eta,
    required this.status,
    required this.onEnRoute,
    required this.onDone,
  });

  final dynamic order;
  final String userName;
  final String? phone;
  final dynamic eta;
  final String status;
  final VoidCallback onEnRoute;
  final VoidCallback onDone;

  Color get _cardColor {
    if (status == 'completed') return RoverColors.primaryContainer;
    if (status == 'en_route') return RoverColors.secondaryContainer;
    return Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = status == 'completed';
    final isEnRoute   = status == 'en_route';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isCompleted
                    ? RoverColors.primary
                    : isEnRoute
                        ? RoverColors.secondary
                        : RoverColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  order?.toString() ?? '?',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: RoverColors.textPrimary,
                    ),
                  ),
                  if (eta != null)
                    Text(
                      'ETA: $eta min',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: RoverColors.textSecondary,
                      ),
                    ),
                  if (phone != null)
                    Text(
                      phone!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: RoverColors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: 6),
                  _StatusChip(status: status),
                ],
              ),
            ),
            // Actions
            if (isCompleted)
              Icon(Icons.check_circle,
                  color: RoverColors.primary, size: 22)
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isEnRoute)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: RoverColors.secondary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                      ),
                      onPressed: onEnRoute,
                      child: Text(
                        'On\nWay',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: RoverColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onPressed: onDone,
                    child: Text(
                      'Done',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status chip — traffic light palette
// ─────────────────────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;

    switch (status) {
      case 'en_route':
        bg    = RoverColors.secondaryContainer;
        fg    = RoverColors.secondary;
        label = 'En Route';
        break;
      case 'completed':
        bg    = RoverColors.primaryContainer;
        fg    = RoverColors.primary;
        label = 'Picked Up';
        break;
      default:
        bg    = RoverColors.surfaceContainerHigh;
        fg    = RoverColors.textSecondary;
        label = 'Waiting';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}
