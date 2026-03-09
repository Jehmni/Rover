// admin_home_page.dart
// Home screen for role = 'admin' / organiser.
// Supports: view events, create event, cancel event, assign driver.
// All mutations are enforced server-side by RLS (admin role check).

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/event_service.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  List<Map<String, dynamic>> _events  = [];
  List<Map<String, dynamic>> _drivers = [];
  bool _isLoading = true;
  bool _isActing  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        EventService.getEvents(),
        EventService.getDrivers(),
      ]);
      setState(() {
        _events  = results[0] as List<Map<String, dynamic>>;
        _drivers = results[1] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Create event dialog ────────────────────────────────────
  void _showCreateEventDialog() {
    final nameCtrl  = TextEditingController();
    final descCtrl  = TextEditingController();
    final typeCtrl  = TextEditingController();
    final locCtrl   = TextEditingController();
    DateTime? pickedDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Create Event'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Event Name *'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Type (Concert, Sports, …)'),
                ),
                TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(labelText: 'Location Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pickedDate == null
                            ? 'No date selected'
                            : 'Date: ${pickedDate!.day}/${pickedDate!.month}/${pickedDate!.year}',
                      ),
                    ),
                    TextButton(
                      child: const Text('Pick Date'),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now().add(const Duration(days: 1)),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                        );
                        if (d != null) setDialogState(() => pickedDate = d);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              child: const Text('Create'),
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || pickedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Name and date are required.'),
                        backgroundColor: Colors.red),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                setState(() => _isActing = true);
                try {
                  await EventService.createEvent(
                    name:         nameCtrl.text.trim(),
                    description:  descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    eventDate:    pickedDate!,
                    eventType:    typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
                    locationName: locCtrl.text.trim().isEmpty ? null : locCtrl.text.trim(),
                  );
                  _showSnack('Event created!', Colors.green);
                  await _load();
                } catch (e) {
                  _showError(e.toString().replaceFirst('Exception: ', ''));
                } finally {
                  if (mounted) setState(() => _isActing = false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Assign driver dialog ───────────────────────────────────
  void _showAssignDriverDialog(int eventId, String eventName) {
    String? selectedDriverId;

    if (_drivers.isEmpty) {
      _showError('No drivers registered in the system yet.');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Assign Driver\n$eventName'),
          content: DropdownButton<String>(
            value: selectedDriverId,
            hint: const Text('Select a driver'),
            isExpanded: true,
            items: _drivers.map((d) => DropdownMenuItem(
              value: d['id'] as String,
              child: Text(d['full_name'] as String? ?? 'Driver'),
            )).toList(),
            onChanged: (val) => setDialogState(() => selectedDriverId = val),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
            ElevatedButton(
              child: const Text('Assign'),
              onPressed: selectedDriverId == null
                  ? null
                  : () async {
                      Navigator.of(ctx).pop();
                      setState(() => _isActing = true);
                      try {
                        // FIX: writes assigned_driver_id (correct column)
                        await EventService.assignDriver(eventId, selectedDriverId!);
                        _showSnack('Driver assigned!', Colors.green);
                        await _load();
                      } catch (e) {
                        _showError(e.toString().replaceFirst('Exception: ', ''));
                      } finally {
                        if (mounted) setState(() => _isActing = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  // ── Cancel event ───────────────────────────────────────────
  Future<void> _cancelEvent(int eventId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Event?'),
        content: Text('This will cancel "$name". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isActing = true);
    try {
      await EventService.cancelEvent(eventId);
      _showSnack('Event cancelled.', Colors.orange);
      await _load();
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
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
        title: const Text('Rover — Admin'),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
        actions: [
          if (_isActing)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateEventDialog,
        backgroundColor: const Color(0xFF478DE0),
        icon: const Icon(Icons.add),
        label: const Text('New Event'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _events.isEmpty
              ? const Center(
                  child: Text('No active events. Tap + to create one.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                    itemCount: _events.length,
                    itemBuilder: (context, index) {
                      final event = _events[index];
                      final eventDate = event['event_date'] != null
                          ? DateTime.tryParse(event['event_date'] as String)
                          : null;
                      final driverName =
                          (event['profiles'] as Map?)?['full_name'] as String?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  event['name'] as String? ?? 'Unnamed',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (eventDate != null)
                                      Text('${eventDate.day}/${eventDate.month}/${eventDate.year}',
                                          style: const TextStyle(color: Colors.grey)),
                                    if (event['event_type'] != null)
                                      Text(event['event_type'] as String,
                                          style: const TextStyle(color: Color(0xFF478DE0))),
                                    Text(
                                      driverName != null
                                          ? 'Driver: $driverName'
                                          : 'No driver assigned',
                                      style: TextStyle(
                                        color: driverName != null ? Colors.green : Colors.orange,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OverflowBar(
                                alignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.directions_bus, size: 18),
                                    label: const Text('Assign Driver'),
                                    onPressed: _isActing
                                        ? null
                                        : () => _showAssignDriverDialog(
                                              event['id'] as int,
                                              event['name'] as String? ?? 'Event',
                                            ),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.cancel, size: 18, color: Colors.red),
                                    label: const Text('Cancel', style: TextStyle(color: Colors.red)),
                                    onPressed: _isActing
                                        ? null
                                        : () => _cancelEvent(
                                              event['id'] as int,
                                              event['name'] as String? ?? 'Event',
                                            ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
