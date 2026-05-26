// event_service.dart
//
// Supabase-backed event service for list/search/detail, CRUD, subscriptions,
// and driver assignment.

import '../main.dart';

class EventService {
  static int _lastRangeIndex(int offset, int limit) {
    final safeLimit = limit.clamp(1, 100).toInt();
    return offset + safeLimit - 1;
  }

  static Map<String, double>? pointFromGeoJson(dynamic point) {
    if (point is! Map) return null;
    final coordinates = point['coordinates'];
    if (coordinates is! List || coordinates.length < 2) return null;
    final lon = (coordinates[0] as num?)?.toDouble();
    final lat = (coordinates[1] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return {'latitude': lat, 'longitude': lon};
  }

  // ─────────────────────────────────────────────────────────
  // LIST all active events, newest first by event_date.
  // Joins admin profile for display name.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEvents({
    int offset = 0,
    int limit = 50,
  }) async {
    // No status filter here — RLS handles it:
    //   regular users: sees active only (policy: status = 'active')
    //   admins: sees all statuses (policy allows admin role)
    final data = await supabase
        .from('events')
        .select(
            '*, admin:profiles!admin_id(full_name), driver:profiles!assigned_driver_id(full_name)')
        .order('event_date', ascending: true)
        .range(offset, _lastRangeIndex(offset, limit));
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // SEARCH events by name, type, and/or date.
  // All three columns exist in the schema.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> searchEvents({
    String? name,
    String? eventType,
    DateTime? fromDate,
    int offset = 0,
    int limit = 50,
  }) async {
    var query = supabase
        .from('events')
        .select(); // RLS filters by status based on caller's role

    if (name != null && name.trim().isNotEmpty) {
      query = query.ilike('name', '%${name.trim()}%');
    }
    if (eventType != null && eventType.trim().isNotEmpty) {
      query = query.eq('event_type', eventType.trim());
    }
    if (fromDate != null) {
      query = query.gte('event_date', fromDate.toIso8601String());
    }

    final data = await query
        .order('event_date', ascending: true)
        .range(offset, _lastRangeIndex(offset, limit));
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // GET a single event's full details.
  // ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getEventDetails(int eventId) async {
    final data = await supabase
        .from('events')
        .select(
            '*, admin:profiles!admin_id(full_name), driver:profiles!assigned_driver_id(full_name, id)')
        .eq('id', eventId)
        .single();
    return Map<String, dynamic>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // CREATE an event. Admin-only; enforced by RLS on the server.
  // ─────────────────────────────────────────────────────────
  static Future<void> createEvent({
    required String name,
    required DateTime eventDate,
    String? description,
    String? locationName,
    String? eventType,
    double? latitude,
    double? longitude,
  }) async {
    if (name.trim().isEmpty) throw Exception('Event name is required.');
    if (eventDate.isBefore(DateTime.now())) {
      throw Exception('Event date must be in the future.');
    }
    // Validate coordinates if provided
    if (latitude != null && (latitude < -90 || latitude > 90)) {
      throw Exception('Latitude must be between -90 and 90.');
    }
    if (longitude != null && (longitude < -180 || longitude > 180)) {
      throw Exception('Longitude must be between -180 and 180.');
    }

    await supabase.from('events').insert({
      'name': name.trim(),
      'description': description?.trim(),
      'event_date': eventDate.toIso8601String(),
      'event_type': eventType?.trim(),
      'location_name': locationName?.trim(),
      // admin_id and org_id are set by the BEFORE INSERT trigger (set_event_defaults)
      // — do not pass them from the client.
      if (latitude != null && longitude != null)
        'location': 'POINT($longitude $latitude)',
    });
  }

  // ─────────────────────────────────────────────────────────
  // UPDATE an event. Admin-only; enforced by RLS.
  // ─────────────────────────────────────────────────────────
  static Future<void> updateEvent(
    int eventId, {
    String? name,
    String? description,
    String? eventType,
    String? locationName,
    DateTime? eventDate,
    double? latitude,
    double? longitude,
  }) async {
    // Fix M-9: validate date on edit, matching the DB CHECK constraint
    // (event_date > now() - interval '1 hour')
    if (eventDate != null &&
        eventDate
            .isBefore(DateTime.now().subtract(const Duration(minutes: 55)))) {
      throw Exception('Event date must not be in the past.');
    }
    if (latitude != null && (latitude < -90 || latitude > 90)) {
      throw Exception('Latitude must be between -90 and 90.');
    }
    if (longitude != null && (longitude < -180 || longitude > 180)) {
      throw Exception('Longitude must be between -180 and 180.');
    }
    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) updates['name'] = name.trim();
    if (description != null) updates['description'] = description.trim();
    if (eventType != null) updates['event_type'] = eventType.trim();
    if (locationName != null) updates['location_name'] = locationName.trim();
    if (eventDate != null) {
      updates['event_date'] = eventDate.toIso8601String();
    }
    if (latitude != null && longitude != null) {
      updates['location'] = 'POINT($longitude $latitude)';
    }
    if (updates.isEmpty) return;

    await supabase.from('events').update(updates).eq('id', eventId);
    await _notifySubscribers(eventId, 'edited');
  }

  // ─────────────────────────────────────────────────────────
  // GET ATTENDEES for an event (admin only).
  // RLS subs_select_admin ensures only the org admin can call this.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEventAttendees(
    int eventId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final data = await supabase
        .from('event_subscriptions')
        .select('user_id, profiles!user_id(full_name, phone)')
        .eq('event_id', eventId)
        .range(offset, _lastRangeIndex(offset, limit));
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // CANCEL an event (soft-delete via status flag). Admin-only.
  // ─────────────────────────────────────────────────────────
  static Future<void> cancelEvent(int eventId) async {
    await supabase
        .from('events')
        .update({'status': 'cancelled'}).eq('id', eventId);
    await _notifySubscribers(eventId, 'cancelled');
  }

  static Future<void> _notifySubscribers(
      int eventId, String notificationType) async {
    try {
      await supabase.functions.invoke(
        'notify-event-subscribers',
        body: {
          'event_id': eventId,
          'notification_type': notificationType,
        },
      );
    } catch (_) {
      // Event updates should remain successful if push notification is down.
    }
  }

  // ─────────────────────────────────────────────────────────
  // SUBSCRIBE the current user to an event.
  // ─────────────────────────────────────────────────────────
  static Future<void> subscribe(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in to subscribe.');

    await supabase.from('event_subscriptions').insert({
      'event_id': eventId,
      'user_id': userId,
    });
    // The UNIQUE(event_id, user_id) constraint in PostgreSQL
    // will throw if the user is already subscribed — no manual
    // duplicate-check query needed.
  }

  // ─────────────────────────────────────────────────────────
  // UNSUBSCRIBE the current user from an event.
  // ─────────────────────────────────────────────────────────
  static Future<void> unsubscribe(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('You must be logged in.');

    await supabase
        .from('event_subscriptions')
        .delete()
        .eq('event_id', eventId)
        .eq('user_id', userId);
  }

  // ─────────────────────────────────────────────────────────
  // CHECK if the current user is subscribed to an event.
  // ─────────────────────────────────────────────────────────
  static Future<bool> isSubscribed(int eventId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final data = await supabase
        .from('event_subscriptions')
        .select('id')
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();
    return data != null;
  }

  // ─────────────────────────────────────────────────────────
  // ASSIGN a driver to an event. Admin-only; enforced by RLS.
  // ─────────────────────────────────────────────────────────
  static Future<void> assignDriver(int eventId, String driverUserId) async {
    await supabase
        .from('events')
        .update({'assigned_driver_id': driverUserId}).eq('id', eventId);
  }

  // ─────────────────────────────────────────────────────────
  // LIST all drivers (profiles with role = 'driver').
  // Used by the admin screen's driver-assignment dropdown.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getDrivers({
    int offset = 0,
    int limit = 100,
  }) async {
    final data = await supabase
        .from('profiles')
        .select('id, full_name, phone')
        .eq('role', 'driver')
        .order('full_name')
        .range(offset, _lastRangeIndex(offset, limit));
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // LIST events assigned to the current driver.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getDriverEvents({
    int offset = 0,
    int limit = 50,
  }) async {
    final driverId = supabase.auth.currentUser?.id;
    if (driverId == null) return [];

    final data = await supabase
        .from('events')
        .select()
        .eq('assigned_driver_id', driverId)
        .eq('status', 'active')
        .order('event_date', ascending: true)
        .range(offset, _lastRangeIndex(offset, limit));
    return List<Map<String, dynamic>>.from(data);
  }
}
