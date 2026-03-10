// event_detail_page.dart
// Shows full details for one event.
// User actions: Subscribe / Unsubscribe, Request Pickup, view live ETA.

import 'package:flutter/material.dart';
import '../services/event_service.dart';
import '../services/pickup_service.dart';

class EventDetailPage extends StatefulWidget {
  final int eventId;
  const EventDetailPage({super.key, required this.eventId});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  Map<String, dynamic>? _event;
  bool _isSubscribed = false;
  bool _isLoading = true;
  bool _isActing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        EventService.getEventDetails(widget.eventId),
        EventService.isSubscribed(widget.eventId),
      ]);
      setState(() {
        _event = results[0] as Map<String, dynamic>;
        _isSubscribed = results[1] as bool;
      });
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleSubscription() async {
    setState(() => _isActing = true);
    try {
      if (_isSubscribed) {
        await EventService.unsubscribe(widget.eventId);
        _showSnack('Unsubscribed from event.', Colors.orange);
      } else {
        await EventService.subscribe(widget.eventId);
        _showSnack('Subscribed successfully!', Colors.green);
      }
      setState(() => _isSubscribed = !_isSubscribed);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _requestPickup() async {
    setState(() => _isActing = true);
    try {
      await PickupService.requestPickup(widget.eventId);
      _showSnack('Pickup requested! You will be notified when the driver is on the way.', Colors.green);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
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
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_event == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Event')),
        body: const Center(child: Text('Event not found.')),
      );
    }

    final adminName = (_event!['admin'] as Map?)?['full_name'] ?? 'Unknown';
    final eventDate = _event!['event_date'] != null
        ? DateTime.tryParse(_event!['event_date'] as String)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_event!['name'] as String? ?? 'Event Details'),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _event!['name'] as String? ?? '',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (eventDate != null)
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '${eventDate.day}/${eventDate.month}/${eventDate.year}  '
                    '${eventDate.hour.toString().padLeft(2, '0')}:'
                    '${eventDate.minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            if (_event!['event_type'] != null) ...[
              const SizedBox(height: 6),
              Chip(
                label: Text(_event!['event_type'] as String),
                backgroundColor: const Color(0xFF73AEF5),
                labelStyle: const TextStyle(color: Colors.white),
              ),
            ],
            if (_event!['location_name'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _event!['location_name'] as String,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            if (_event!['description'] != null)
              Text(
                _event!['description'] as String,
                style: const TextStyle(fontSize: 16, height: 1.5),
              ),
            const SizedBox(height: 8),
            Text(
              'Organised by: $adminName',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Spacer(),
            // Live ETA card — shown once user has a pickup request
            StreamBuilder<Map<String, dynamic>?>(
              stream: PickupService.listenToMyPickup(widget.eventId),
              builder: (context, snapshot) {
                final pickup = snapshot.data;
                if (pickup == null) return const SizedBox.shrink();
                return Card(
                  color: const Color(0xFFE8F4FD),
                  child: ListTile(
                    leading: const Icon(Icons.directions_bus, color: Color(0xFF478DE0)),
                    title: Text('Pickup #${pickup['pickup_order'] ?? '-'}'),
                    subtitle: Text(
                      pickup['eta_minutes'] != null
                          ? 'ETA: ${pickup['eta_minutes']} min  •  Status: ${pickup['status']}'
                          : 'Status: ${pickup['status']}',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isActing ? null : _toggleSubscription,
                    icon: Icon(_isSubscribed ? Icons.remove_circle_outline : Icons.add_circle_outline),
                    label: Text(_isSubscribed ? 'Unsubscribe' : 'Subscribe'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isSubscribed ? Colors.orange : const Color(0xFF478DE0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_isActing || !_isSubscribed) ? null : _requestPickup,
                    icon: const Icon(Icons.local_taxi),
                    label: const Text('Request Pickup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
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
