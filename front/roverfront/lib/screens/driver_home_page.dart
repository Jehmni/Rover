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
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/pickup_service.dart';
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
      _showSnack('Route optimised — ${ordered.length} pickup(s) scheduled.', Colors.green);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isScheduling = false);
    }
  }

  Future<void> _markEnRoute(int pickupId) async {
    try {
      await PickupService.markEnRoute(pickupId);
      _showSnack('Status updated — en route.', Colors.blue);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _markCompleted(int pickupId) async {
    try {
      await PickupService.markCompleted(pickupId);
      _showSnack('Pickup marked as completed.', Colors.green);
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
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
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
      appBar: AppBar(
        title: const Text('Rover — Driver'),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
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
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      // "View Map" FAB — only visible once a route has been started
      floatingActionButton: _activeEventId != null
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF478DE0),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.map),
              label: const Text('View Map'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DriverMapPage(
                    eventId:   _activeEventId!,
                    eventName: _activeEventName ?? 'Route',
                    profilesCache: _profilesCache,
                  ),
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Assigned events ──────────────────────────
                if (_assignedEvents.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No events assigned to you yet.',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Assigned Events',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...(_assignedEvents.map((event) {
                          final eventDate = event['event_date'] != null
                              ? DateTime.tryParse(
                                  event['event_date'] as String)
                              : null;
                          final isActive =
                              _activeEventId == event['id'] as int;
                          return Card(
                            color: isActive
                                ? Colors.blue[50]
                                : null,
                            child: ListTile(
                              title: Text(event['name'] as String? ?? 'Unnamed'),
                              subtitle: eventDate != null
                                  ? Text(
                                      '${eventDate.day}/${eventDate.month}/${eventDate.year}'
                                      '  ${eventDate.hour.toString().padLeft(2, '0')}:'
                                      '${eventDate.minute.toString().padLeft(2, '0')}',
                                    )
                                  : null,
                              trailing: ElevatedButton.icon(
                                icon: _isScheduling &&
                                        _activeEventId == event['id'] as int
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : Icon(
                                        isActive
                                            ? Icons.refresh
                                            : Icons.play_arrow,
                                        size: 18),
                                label: Text(isActive
                                    ? 'Re-route'
                                    : 'Start Route'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isActive
                                      ? Colors.orange
                                      : Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _isScheduling
                                    ? null
                                    : () => _startRoute(
                                          event['id'] as int,
                                          event['name'] as String? ?? 'Event',
                                        ),
                              ),
                            ),
                          );
                        })),
                      ],
                    ),
                  ),

                // ── Live pickup order (realtime stream) ──────
                if (_activeEventId != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Pickup Order — $_activeEventName',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Text(
                          '${_pickupOrder.where((p) => p['status'] != 'completed').length} remaining',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: PickupService.listenToPickupUpdates(
                          _activeEventId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                                ConnectionState.waiting &&
                            _pickupOrder.isEmpty) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final pickups =
                            snapshot.hasData && snapshot.data!.isNotEmpty
                                ? snapshot.data!
                                : _pickupOrder;

                        if (pickups.isEmpty) {
                          return const Center(
                            child: Text('No pickup requests yet.'),
                          );
                        }

                        return ListView.builder(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: pickups.length,
                          itemBuilder: (context, i) {
                            final p      = pickups[i];
                            final order  = p['pickup_order'];
                            final eta    = p['eta_minutes'];
                            final status = p['status'] as String? ?? 'pending';

                            // Fix M-3: resolve name/phone from pre-fetched cache
                            final userId  = p['user_id'] as String? ?? '';
                            final profile = _profilesCache[userId];
                            final userName =
                                profile?['full_name'] as String? ?? 'Passenger';
                            final phone = profile?['phone'] as String?;

                            final isCompleted = status == 'completed';
                            final isEnRoute   = status == 'en_route';

                            return Card(
                              color: isCompleted
                                  ? Colors.green[50]
                                  : isEnRoute
                                      ? Colors.blue[50]
                                      : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isCompleted
                                      ? Colors.green
                                      : isEnRoute
                                          ? Colors.blue
                                          : const Color(0xFF478DE0),
                                  child: Text(
                                    order?.toString() ?? '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(userName),
                                subtitle: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    if (eta != null)
                                      Text('ETA: $eta min'),
                                    if (phone != null)
                                      Text('Phone: $phone'),
                                    _statusChip(status),
                                  ],
                                ),
                                // Fix L-2: show en_route and completed actions
                                trailing: isCompleted
                                    ? const Icon(Icons.check_circle,
                                        color: Colors.green)
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!isEnRoute)
                                            TextButton(
                                              style: TextButton.styleFrom(
                                                foregroundColor: Colors.blue,
                                              ),
                                              child: const Text('On\nWay',
                                                  textAlign:
                                                      TextAlign.center,
                                                  style: TextStyle(
                                                      fontSize: 11)),
                                              onPressed: () => _markEnRoute(
                                                  p['id'] as int),
                                            ),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.green,
                                            ),
                                            child: const Text('Done'),
                                            onPressed: () => _markCompleted(
                                                p['id'] as int),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    String label;
    switch (status) {
      case 'en_route':
        bg    = Colors.blue;
        label = 'En Route';
        break;
      case 'completed':
        bg    = Colors.green;
        label = 'Picked Up';
        break;
      default:
        bg    = Colors.grey;
        label = 'Waiting';
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11, color: bg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
