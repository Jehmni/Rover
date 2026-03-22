// driver_map_page.dart
//
// Full-screen map view for the driver during a live pickup route.
//
// Features:
//   - OpenStreetMap tiles via flutter_map (no API key required)
//   - Driver's current GPS position shown as a car marker
//   - Each pending/en_route pickup shown as a numbered circle marker
//   - Completed pickups shown as a greyed-out check marker
//   - Live updates via PickupService.listenToPickupUpdates (realtime stream)
//   - Bottom sheet lists all stops; tap a row to centre the map on that stop
//   - "On My Way" / "Done" actions directly from the bottom sheet
//   - Map auto-fits all markers on first load

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/pickup_service.dart';

class DriverMapPage extends StatefulWidget {
  const DriverMapPage({
    super.key,
    required this.eventId,
    required this.eventName,
    required this.profilesCache,
  });

  final int    eventId;
  final String eventName;

  /// Pre-fetched userId → {full_name, phone} map from DriverHomePage.
  /// Passed in because realtime .stream() cannot join profiles.
  final Map<String, Map<String, dynamic>> profilesCache;

  @override
  State<DriverMapPage> createState() => _DriverMapPageState();
}

class _DriverMapPageState extends State<DriverMapPage> {
  final MapController _mapController = MapController();

  LatLng? _driverPosition;
  StreamSubscription<Position>? _positionSub;

  // Updated by the realtime stream
  List<Map<String, dynamic>> _pickups = [];

  bool _initialFitDone = false;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // ── Driver location tracking ───────────────────────────────
  Future<void> _startLocationTracking() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return;

    // Seed with current position immediately
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() => _driverPosition = LatLng(pos.latitude, pos.longitude));
      }
    } catch (_) {}

    // Then stream updates
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy:           LocationAccuracy.high,
        distanceFilter:     10, // metres — only update when moved 10 m
      ),
    ).listen((pos) {
      if (mounted) {
        setState(() => _driverPosition = LatLng(pos.latitude, pos.longitude));
      }
    });
  }

  // ── Actions ───────────────────────────────────────────────
  Future<void> _markEnRoute(int id) async {
    try {
      await PickupService.markEnRoute(id);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _markCompleted(int id) async {
    try {
      await PickupService.markCompleted(id);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── Fit map to all markers ─────────────────────────────────
  void _fitBounds(List<Map<String, dynamic>> pickups) {
    final points = <LatLng>[];
    if (_driverPosition != null) points.add(_driverPosition!);
    for (final p in pickups) {
      final ll = _latLngFromPickup(p);
      if (ll != null) points.add(ll);
    }
    if (points.isEmpty) return;

    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }

    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
    );
  }

  // ── Parse pickup_location ──────────────────────────────────
  // When fetched via realtime stream the location column comes back
  // as a GeoJSON map: { type: 'Point', coordinates: [lon, lat] }
  LatLng? _latLngFromPickup(Map<String, dynamic> p) {
    final loc = p['pickup_location'];
    if (loc == null) return null;
    if (loc is Map) {
      final coords = loc['coordinates'];
      if (coords is List && coords.length >= 2) {
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        return LatLng(lat, lon);
      }
    }
    return null;
  }

  // ── Centre map on a specific pickup ───────────────────────
  void _centreOn(Map<String, dynamic> pickup) {
    final ll = _latLngFromPickup(pickup);
    if (ll != null) _mapController.move(ll, 16);
  }

  // ── Marker colour by status ────────────────────────────────
  Color _markerColor(String status) {
    switch (status) {
      case 'en_route':  return Colors.blue;
      case 'completed': return Colors.grey;
      default:          return const Color(0xFF478DE0);
    }
  }

  // ── Build markers list ─────────────────────────────────────
  List<Marker> _buildMarkers(List<Map<String, dynamic>> pickups) {
    final markers = <Marker>[];

    // Driver marker
    if (_driverPosition != null) {
      markers.add(
        Marker(
          point:  _driverPosition!,
          width:  48,
          height: 48,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green, width: 3),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
            ),
            child: const Icon(Icons.directions_car, color: Colors.green, size: 26),
          ),
        ),
      );
    }

    // Pickup markers
    for (final p in pickups) {
      final ll = _latLngFromPickup(p);
      if (ll == null) continue;

      final order     = p['pickup_order'] as int?;
      final status    = p['status'] as String? ?? 'pending';
      final isCompleted = status == 'completed';
      final color     = _markerColor(status);

      markers.add(
        Marker(
          point:  ll,
          width:  44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.grey[300]
                  : color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
            ),
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 22)
                : Center(
                    child: Text(
                      order?.toString() ?? '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _driverPosition ?? const LatLng(51.5, -0.09);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.eventName),
        backgroundColor: const Color(0xFF478DE0),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Centre on me',
            onPressed: () {
              if (_driverPosition != null) {
                _mapController.move(_driverPosition!, 15);
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.fit_screen),
            tooltip: 'Fit all stops',
            onPressed: () => _fitBounds(_pickups),
          ),
        ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: PickupService.listenToPickupUpdates(widget.eventId),
        builder: (context, snapshot) {
          // On first data, fit map to all markers
          if (snapshot.hasData && !_initialFitDone) {
            _pickups = snapshot.data!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitBounds(_pickups);
            });
            _initialFitDone = true;
          } else if (snapshot.hasData) {
            _pickups = snapshot.data!;
          }

          final pickups = _pickups;
          final pending = pickups
              .where((p) => p['status'] != 'completed')
              .length;

          return Column(
            children: [
              // ── Summary banner ────────────────────────────
              Container(
                color: const Color(0xFF478DE0),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '$pending stop${pending == 1 ? '' : 's'} remaining'
                      ' of ${pickups.length}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),

              // ── Map ───────────────────────────────────────
              Expanded(
                flex: 3,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom:   13,
                  ),
                  children: [
                    // OpenStreetMap tiles — no API key required
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'io.rover.app',
                    ),
                    MarkerLayer(markers: _buildMarkers(pickups)),
                  ],
                ),
              ),

              // ── Pickup list ───────────────────────────────
              Expanded(
                flex: 2,
                child: pickups.isEmpty
                    ? const Center(
                        child: Text(
                          'No pickups for this event.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: pickups.length,
                        itemBuilder: (context, i) {
                          final p       = pickups[i];
                          final order   = p['pickup_order'] as int?;
                          final eta     = p['eta_minutes'] as int?;
                          final status  = p['status'] as String? ?? 'pending';
                          final userId  = p['user_id'] as String? ?? '';
                          final profile = widget.profilesCache[userId];
                          final name    = profile?['full_name'] as String?
                              ?? 'Passenger';
                          final phone   = profile?['phone'] as String?;

                          final isCompleted = status == 'completed';
                          final isEnRoute   = status == 'en_route';
                          final color       = _markerColor(status);

                          return ListTile(
                            onTap: () => _centreOn(p),
                            leading: CircleAvatar(
                              backgroundColor:
                                  isCompleted ? Colors.grey[300] : color,
                              child: isCompleted
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 18)
                                  : Text(
                                      order?.toString() ?? '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                            title: Text(
                              name,
                              style: TextStyle(
                                decoration: isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: isCompleted ? Colors.grey : null,
                              ),
                            ),
                            subtitle: Text([
                              if (eta != null) 'ETA $eta min',
                              if (phone != null) phone,
                              _statusLabel(status),
                            ].join('  •  ')),
                            trailing: isCompleted
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isEnRoute)
                                        IconButton(
                                          icon: const Icon(
                                              Icons.directions_car,
                                              color: Colors.blue),
                                          tooltip: 'Mark en route',
                                          onPressed: () =>
                                              _markEnRoute(p['id'] as int),
                                        ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.check_circle_outline,
                                            color: Colors.green),
                                        tooltip: 'Mark picked up',
                                        onPressed: () =>
                                            _markCompleted(p['id'] as int),
                                      ),
                                    ],
                                  ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'en_route':  return 'En Route';
      case 'completed': return 'Picked Up';
      default:          return 'Waiting';
    }
  }
}
