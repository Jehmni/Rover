// event_detail_page.dart
// Shows full details for one event.
// User actions: Subscribe / Unsubscribe, Request Pickup, view live ETA.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../services/event_service.dart';
import '../services/pickup_service.dart';
import '../theme/rover_theme.dart';
import 'user_guide_page.dart';

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
  // Fix L-6: tracks whether this user has a pending/en_route pickup request
  // so the "Request Pickup" button is replaced with a persistent indicator.
  bool _hasPickup = false;

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
        PickupService.hasActivePickup(widget.eventId),
      ]);
      setState(() {
        _event = results[0] as Map<String, dynamic>;
        _isSubscribed = results[1] as bool;
        _hasPickup = results[2] as bool;
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
        _showSnack('Unsubscribed from event.', RoverColors.secondary);
      } else {
        await EventService.subscribe(widget.eventId);
        _showSnack('Subscribed successfully!', RoverColors.primary);
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
      // Fix L-6: set persistent state so button becomes an indicator
      if (mounted) setState(() => _hasPickup = true);
      _showSnack(
          'Pickup requested! You will be notified when the driver is on the way.',
          RoverColors.primary);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _cancelPickup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Pickup?'),
        content: const Text(
          'Your pickup request will be removed from the driver route.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Pickup'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: RoverColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Cancel Pickup',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isActing = true);
    try {
      await PickupService.cancelPickup(widget.eventId);
      if (mounted) setState(() => _hasPickup = false);
      _showSnack('Pickup cancelled.', RoverColors.secondary);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
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
    final eventName = _event!['name'] as String? ?? 'Event Details';
    final eventType = _event!['event_type'] as String?;
    final location = _event!['location_name'] as String?;
    final desc = _event!['description'] as String?;

    return Scaffold(
      backgroundColor: RoverColors.surface,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: RoverColors.primary,
            foregroundColor: Colors.white,
            expandedHeight: 140,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.fromLTRB(20, 0, 60, 16),
              title: Text(
                eventName,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              background: Container(color: RoverColors.primary),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.help_outline),
                tooltip: 'Help',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const UserGuidePage(role: 'user'),
                  ),
                ),
              ),
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Event metadata card
                _InfoCard(
                  children: [
                    if (eventDate != null)
                      _InfoRow(
                        icon: Icons.calendar_today,
                        text:
                            '${eventDate.day}/${eventDate.month}/${eventDate.year}  '
                            '${eventDate.hour.toString().padLeft(2, '0')}:'
                            '${eventDate.minute.toString().padLeft(2, '0')}',
                      ),
                    if (location != null) ...[
                      const SizedBox(height: 10),
                      _InfoRow(icon: Icons.location_on, text: location),
                    ],
                    if (eventType != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: RoverColors.secondaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          eventType,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: RoverColors.secondary,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _InfoRow(
                      icon: Icons.person_outline,
                      text: 'Organised by $adminName',
                      small: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Description
                if (desc != null) ...[
                  _InfoCard(
                    children: [
                      Text(
                        desc,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: RoverColors.textPrimary,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],

                // Live ETA card
                StreamBuilder<Map<String, dynamic>?>(
                  stream: PickupService.listenToMyPickup(widget.eventId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 4,
                        child: LinearProgressIndicator(),
                      );
                    }
                    if (snapshot.hasError) {
                      return _InfoCard(
                        color: RoverColors.secondaryContainer,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.warning_amber,
                                  color: RoverColors.secondary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Could not load pickup status. Check your connection.',
                                  style: GoogleFonts.inter(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    final pickup = snapshot.data;
                    if (pickup == null) return const SizedBox.shrink();

                    final hasDriver = _event!['assigned_driver_id'] != null;
                    if (!hasDriver) {
                      return _InfoCard(
                        color: RoverColors.primaryContainer,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.hourglass_empty,
                                  color: RoverColors.primary, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Pickup request received',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.w600,
                                        color: RoverColors.primary,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Waiting for a driver to be assigned.',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: RoverColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    final driverId = _event!['assigned_driver_id'] as String?;

                    return _InfoCard(
                      color: RoverColors.primaryContainer,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.directions_bus,
                                color: RoverColors.primary, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pickup #${pickup['pickup_order'] ?? '-'}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      color: RoverColors.primary,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    pickup['eta_minutes'] != null
                                        ? 'ETA: ${pickup['eta_minutes']} min  •  Status: ${pickup['status']}'
                                        : 'Status: ${pickup['status']}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: RoverColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (driverId != null) ...[
                          const SizedBox(height: 14),
                          _DriverLocationPanel(driverId: driverId),
                        ],
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isActing ? null : _toggleSubscription,
                        icon: Icon(
                          _isSubscribed
                              ? Icons.remove_circle_outline
                              : Icons.add_circle_outline,
                          size: 18,
                        ),
                        label: Text(
                          _isSubscribed ? 'Unsubscribe' : 'Subscribe',
                          style: GoogleFonts.inter(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: _isSubscribed
                              ? RoverColors.secondary
                              : RoverColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Fix L-6: once a pickup is requested, replace the button
                    // with a persistent "Pickup Requested" indicator.
                    Expanded(
                      child: _hasPickup
                          ? Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: RoverColors.primaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle,
                                      color: RoverColors.primary, size: 18),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'Pickup Requested',
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: RoverColors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: (_isActing || !_isSubscribed)
                                  ? null
                                  : _requestPickup,
                              icon: const Icon(Icons.local_taxi, size: 18),
                              label: Text(
                                'Request Pickup',
                                style: GoogleFonts.inter(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: RoverColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                    ),
                  ],
                ),
                if (_hasPickup) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isActing ? null : _cancelPickup,
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: Text(
                        'Cancel Pickup',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: RoverColors.error,
                        side: const BorderSide(color: RoverColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverLocationPanel extends StatelessWidget {
  const _DriverLocationPanel({required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: PickupService.listenToDriverLocation(driverId),
      builder: (context, snapshot) {
        final location = snapshot.data;
        if (location == null) {
          return Row(
            children: [
              Icon(Icons.location_searching,
                  size: 16, color: RoverColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Driver location will appear when the route starts.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: RoverColors.textSecondary,
                  ),
                ),
              ),
            ],
          );
        }

        final lat = location['latitude'] as double;
        final lon = location['longitude'] as double;
        final point = LatLng(lat, lon);
        final driverName = location['full_name'] as String? ?? 'Driver';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.near_me, size: 16, color: RoverColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$driverName location',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: RoverColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 150,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 14,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.drag |
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.jehmni.roverfront',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 42,
                          height: 42,
                          child: Container(
                            decoration: BoxDecoration(
                              color: RoverColors.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.directions_bus,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: RoverColors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helper widgets
// ─────────────────────────────────────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children, this.color});
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    this.small = false,
  });
  final IconData icon;
  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: small ? 14 : 16, color: RoverColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: small ? 12 : 14,
              color:
                  small ? RoverColors.textSecondary : RoverColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
