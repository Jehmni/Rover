// driver_home_page.dart
// Home screen for role = 'driver'.
// Shows events assigned to this driver. Lets the driver start
// route optimization and view live pickup order + ETAs.

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';
import '../services/pickup_service.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  List<Map<String, dynamic>> _assignedEvents = [];
  bool _isLoading = true;

  // Currently selected event for pickup management
  int? _activeEventId;
  String? _activeEventName;
  bool _isScheduling = false;
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

  // Calls the schedule-pickup Edge Function to compute & persist optimal order
  Future<void> _startRoute(int eventId, String eventName) async {
    setState(() { _isScheduling = true; _activeEventId = eventId; _activeEventName = eventName; });
    try {
      final ordered = await PickupService.scheduleRoute(eventId);
      setState(() => _pickupOrder = ordered);
      _showSnack('Route optimized — ${ordered.length} pickup(s) scheduled.', Colors.green);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isScheduling = false);
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
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Assigned events ──────────────────────
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
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ...(_assignedEvents.map((event) {
                          final eventDate = event['event_date'] != null
                              ? DateTime.tryParse(event['event_date'] as String)
                              : null;
                          return Card(
                            child: ListTile(
                              title: Text(event['name'] as String? ?? 'Unnamed'),
                              subtitle: eventDate != null
                                  ? Text('${eventDate.day}/${eventDate.month}/${eventDate.year}')
                                  : null,
                              trailing: ElevatedButton.icon(
                                icon: _isScheduling && _activeEventId == event['id']
                                    ? const SizedBox(
                                        width: 16, height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.play_arrow, size: 18),
                                label: const Text('Start Route'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
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

                // ── Live pickup order (realtime stream) ──
                if (_activeEventId != null) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Pickup Order — $_activeEventName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: PickupService.listenToPickupUpdates(_activeEventId!),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting &&
                            _pickupOrder.isEmpty) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final pickups = snapshot.hasData && snapshot.data!.isNotEmpty
                            ? snapshot.data!
                            : _pickupOrder;

                        if (pickups.isEmpty) {
                          return const Center(
                            child: Text('No pickup requests yet.'),
                          );
                        }

                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: pickups.length,
                          itemBuilder: (context, i) {
                            final p = pickups[i];
                            final order = p['pickup_order'];
                            final eta = p['eta_minutes'];
                            final status = p['status'] as String? ?? 'pending';
                            final userName = (p['profiles'] as Map?)?['full_name'] ?? 'User';
                            final phone = (p['profiles'] as Map?)?['phone'];

                            return Card(
                              color: status == 'completed'
                                  ? Colors.green[50]
                                  : status == 'en_route'
                                      ? Colors.blue[50]
                                      : null,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: status == 'completed'
                                      ? Colors.green
                                      : const Color(0xFF478DE0),
                                  child: Text(
                                    order?.toString() ?? '?',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                title: Text(userName),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (eta != null) Text('ETA: $eta min'),
                                    if (phone != null) Text('Phone: $phone'),
                                    Text('Status: $status'),
                                  ],
                                ),
                                trailing: status != 'completed'
                                    ? TextButton(
                                        child: const Text('Done'),
                                        onPressed: () => _markCompleted(p['id'] as int),
                                      )
                                    : const Icon(Icons.check_circle, color: Colors.green),
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
}
