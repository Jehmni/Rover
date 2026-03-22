// pickup_service.dart
//
// Fixes applied in this revision:
//   M-5  — fcm_token removed from getPickupRequests select (was exposed to driver client)
//   M-10 — cancelPickup now filters status != 'completed' (can't delete completed pickups)
//   M-3  — getPickupProfiles() fetches userId→profile map for realtime stream cross-reference
//   L-2  — markEnRoute() added so driver can transition pending → en_route
//   H-3  — UNIQUE(event_id, user_id) now enforced at DB; client check remains as UX guard

import 'package:geolocator/geolocator.dart';
import '../main.dart';

class PickupService {
  // ─────────────────────────────────────────────────────────
  // REQUEST A PICKUP
  // User submits their current GPS location for an event.
  // ─────────────────────────────────────────────────────────
  static Future<void> requestPickup(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in.');

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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    if (position.latitude < -90 || position.latitude > 90) {
      throw Exception('Invalid GPS latitude: ${position.latitude}');
    }
    if (position.longitude < -180 || position.longitude > 180) {
      throw Exception('Invalid GPS longitude: ${position.longitude}');
    }

    // UX guard — DB UNIQUE constraint (schema_v6) is the real guarantee
    final existing = await supabase
        .from('pickup_requests')
        .select('id')
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) {
      throw Exception('You already have a pickup request for this event.');
    }

    // PostGIS WKT: 'POINT(longitude latitude)'
    await supabase.from('pickup_requests').insert({
      'event_id':        eventId,
      'user_id':         userId,
      'pickup_location': 'POINT(${position.longitude} ${position.latitude})',
      'status':          'pending',
    });
  }

  // ─────────────────────────────────────────────────────────
  // CHECK IF USER HAS AN ACTIVE (non-completed) PICKUP REQUEST
  // Used by EventDetailPage to show the correct button state on load.
  // ─────────────────────────────────────────────────────────
  static Future<bool> hasActivePickup(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await supabase
        .from('pickup_requests')
        .select('id')
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .neq('status', 'completed')
        .maybeSingle();
    return row != null;
  }

  // ─────────────────────────────────────────────────────────
  // CANCEL A PICKUP REQUEST
  // Fix M-10: only deletes non-completed rows.
  // ─────────────────────────────────────────────────────────
  static Future<void> cancelPickup(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in.');

    final existing = await supabase
        .from('pickup_requests')
        .select('id, status')
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      throw Exception('No pickup request found for this event.');
    }
    if (existing['status'] == 'completed') {
      throw Exception('This pickup has already been completed and cannot be cancelled.');
    }

    await supabase
        .from('pickup_requests')
        .delete()
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .neq('status', 'completed');
  }

  // ─────────────────────────────────────────────────────────
  // SCHEDULE ROUTE (driver action)
  // Calls the schedule-pickup Edge Function.
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
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    if (position.latitude < -90 || position.latitude > 90 ||
        position.longitude < -180 || position.longitude > 180) {
      throw Exception('Invalid GPS coordinates from device.');
    }

    final response = await supabase.functions.invoke(
      'schedule-pickup',
      body: {
        'event_id':   eventId,
        'driver_lat': position.latitude,
        'driver_lon': position.longitude,
      },
    );

    if (response.data == null) {
      throw Exception('schedule-pickup function returned no data.');
    }

    // Surface Edge Function errors clearly instead of silently returning []
    if (response.data is Map && response.data['error'] != null) {
      throw Exception(response.data['error'].toString());
    }

    final ordered = response.data['ordered'] as List<dynamic>? ?? [];
    return ordered.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ─────────────────────────────────────────────────────────
  // GET PICKUP REQUESTS (sorted by pickup_order)
  // Fix M-5: fcm_token removed — it must not be sent to driver devices.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPickupRequests(int eventId) async {
    final data = await supabase
        .from('pickup_requests')
        .select('*, profiles!user_id(full_name, phone)')
        .eq('event_id', eventId)
        .order('pickup_order', ascending: true, nullsFirst: false);
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // GET PICKUP PROFILES — userId → { full_name, phone }
  // Fix M-3: realtime .stream() cannot join profiles, so we pre-fetch
  // a profile map and cross-reference against stream rows in the UI.
  // ─────────────────────────────────────────────────────────
  static Future<Map<String, Map<String, dynamic>>> getPickupProfiles(
      int eventId) async {
    final data = await supabase
        .from('pickup_requests')
        .select('user_id, profiles!user_id(full_name, phone)')
        .eq('event_id', eventId);

    final Map<String, Map<String, dynamic>> result = {};
    for (final row in data as List) {
      final userId  = row['user_id'] as String?;
      final profile = row['profiles'] as Map?;
      if (userId != null && profile != null) {
        result[userId] = {
          'full_name': profile['full_name'],
          'phone':     profile['phone'],
        };
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────
  // MARK A PICKUP AS EN_ROUTE
  // Fix L-2: driver transitions pending → en_route before arrival.
  // ─────────────────────────────────────────────────────────
  static Future<void> markEnRoute(int pickupRequestId) async {
    await supabase
        .from('pickup_requests')
        .update({'status': 'en_route'})
        .eq('id', pickupRequestId);
  }

  // ─────────────────────────────────────────────────────────
  // MARK A PICKUP AS COMPLETED
  // ─────────────────────────────────────────────────────────
  static Future<void> markCompleted(int pickupRequestId) async {
    await supabase
        .from('pickup_requests')
        .update({'status': 'completed'})
        .eq('id', pickupRequestId);
  }

  // ─────────────────────────────────────────────────────────
  // REALTIME — driver watches all pickups for an event
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
  // REALTIME — user watches their own pickup for a single event
  // Fix L-7: filters to active statuses only (hides completed ETA)
  // ─────────────────────────────────────────────────────────
  static Stream<Map<String, dynamic>?> listenToMyPickup(int eventId) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value(null);

    return supabase
        .from('pickup_requests')
        .stream(primaryKey: ['id'])
        .eq('event_id', eventId)
        .map((rows) {
          final active = rows.cast<Map<String, dynamic>>().where(
            (r) =>
                r['user_id'] == userId &&
                r['status'] != 'completed',  // hide completed rows from ETA card
          );
          return active.isNotEmpty
              ? Map<String, dynamic>.from(active.first)
              : null;
        });
  }
}
