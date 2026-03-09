// pickup_service.dart
//
// Replaces ALL HTTP calls to:
//   POST /api/pickups/schedule
//   POST /api/pickups/cancel
//   POST /api/pickup/start
//
// Fixes applied vs rover.py:
//   Bug 1 — routes NameError: no variable used before assignment;
//            all routing logic lives in the schedule-pickup Edge Function
//   Bug 3 — users list indexed by DB primary key: no list indexing at all;
//            the DB query returns the right row directly
//   Missing lat — old schedule_pickup read longitude but forgot latitude;
//                  geolocator gives both correctly

import 'package:geolocator/geolocator.dart';
import '../main.dart';

class PickupService {
  // ─────────────────────────────────────────────────────────
  // REQUEST A PICKUP
  // User submits their current GPS location for an event.
  // Both latitude AND longitude are read from the Position object.
  // Coordinates are validated before any DB write.
  // ─────────────────────────────────────────────────────────
  static Future<void> requestPickup(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in.');

    // Check and request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission is required to request a pickup.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission is permanently denied. Enable it in device settings.');
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Validate coordinates before storing (Phase 6 rules)
    if (position.latitude < -90 || position.latitude > 90) {
      throw Exception('Invalid GPS latitude: ${position.latitude}');
    }
    if (position.longitude < -180 || position.longitude > 180) {
      throw Exception('Invalid GPS longitude: ${position.longitude}');
    }

    // Check if a pending request already exists for this user + event
    final existing = await supabase
        .from('pickup_requests')
        .select('id')
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .eq('status', 'pending')
        .maybeSingle();

    if (existing != null) {
      throw Exception('You already have a pending pickup request for this event.');
    }

    // PostGIS expects WKT format: 'POINT(longitude latitude)'
    // Note order: longitude first, then latitude (GeoJSON / PostGIS standard)
    await supabase.from('pickup_requests').insert({
      'event_id': eventId,
      'user_id': userId,
      'pickup_location': 'POINT(${position.longitude} ${position.latitude})',
      'status': 'pending',
    });
  }

  // ─────────────────────────────────────────────────────────
  // CANCEL A PICKUP REQUEST
  // ─────────────────────────────────────────────────────────
  static Future<void> cancelPickup(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in.');

    final existing = await supabase
        .from('pickup_requests')
        .select('id')
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      throw Exception('No pickup request found for this event.');
    }

    await supabase
        .from('pickup_requests')
        .delete()
        .eq('event_id', eventId)
        .eq('user_id', userId);
  }

  // ─────────────────────────────────────────────────────────
  // SCHEDULE ROUTE (driver action)
  // Calls the schedule-pickup Edge Function which:
  //   1. Fetches all pending pickup_requests for the event
  //   2. Runs greedy nearest-neighbor ordering (O(n²))
  //   3. Writes pickup_order + eta_minutes to each row
  //   4. Notifies the first user via FCM
  //
  // Returns the ordered list with ETA for the driver's UI.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> scheduleRoute(int eventId) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission is required.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission is permanently denied. Enable it in device settings.');
    }

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    // Validate driver coordinates
    if (position.latitude < -90 || position.latitude > 90 ||
        position.longitude < -180 || position.longitude > 180) {
      throw Exception('Invalid GPS coordinates from device.');
    }

    final response = await supabase.functions.invoke(
      'schedule-pickup',
      body: {
        'event_id': eventId,
        'driver_lat': position.latitude,
        'driver_lon': position.longitude,
      },
    );

    if (response.data == null) {
      throw Exception('schedule-pickup function returned no data.');
    }

    final ordered = response.data['ordered'] as List<dynamic>? ?? [];
    return ordered.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─────────────────────────────────────────────────────────
  // GET PICKUP REQUESTS for an event (sorted by pickup_order).
  // Used by the driver screen to display the pickup sequence.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPickupRequests(int eventId) async {
    final data = await supabase
        .from('pickup_requests')
        .select('*, profiles!user_id(full_name, phone, fcm_token)')
        .eq('event_id', eventId)
        .order('pickup_order', ascending: true, nullsFirst: false);
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // MARK A PICKUP AS COMPLETED
  // Called by the driver after picking up a user.
  // ─────────────────────────────────────────────────────────
  static Future<void> markCompleted(int pickupRequestId) async {
    await supabase
        .from('pickup_requests')
        .update({'status': 'completed'})
        .eq('id', pickupRequestId);
  }

  // ─────────────────────────────────────────────────────────
  // REALTIME LISTENER
  // Driver screen subscribes to live pickup_requests changes
  // so the list auto-updates as statuses change.
  // ─────────────────────────────────────────────────────────
  static Stream<List<Map<String, dynamic>>> listenToPickupUpdates(int eventId) {
    return supabase
        .from('pickup_requests')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .order('pickup_order', ascending: true)
        .map((rows) => List<Map<String, dynamic>>.from(rows));
  }

  // ─────────────────────────────────────────────────────────
  // USER'S OWN PICKUP STATUS (realtime)
  // User screen shows live ETA and status for their request.
  // ─────────────────────────────────────────────────────────
  static Stream<Map<String, dynamic>?> listenToMyPickup(int eventId) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value(null);

    return supabase
        .from('pickup_requests')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .map((rows) {
          // Find this user's row in the stream result
          final myRow = rows.cast<Map<String, dynamic>>().where(
            (r) => r['user_id'] == userId,
          );
          return myRow.isNotEmpty
              ? Map<String, dynamic>.from(myRow.first)
              : null;
        });
  }
}
