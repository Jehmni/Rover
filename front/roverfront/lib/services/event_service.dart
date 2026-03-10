// event_service.dart
//
// Replaces ALL HTTP calls to:
//   GET    /api/events               (new — list all active events)
//   GET    /api/events/search        (was broken — Event.location/date/type missing)
//   GET    /api/event/<id>/details
//   POST   /api/event/create
//   PUT    /api/event/<id>/update
//   DELETE /api/event/<id>/cancel
//   POST   /api/events/<id>/subscribe
//   POST   /api/events/<id>/unsubscribe
//   POST   /api/events/<id>/assign-driver
//
// Fixes applied vs rover.py:
//   Bug 4 — old code wrote event.driver_id; correct column is assigned_driver_id
//   Bug 5 — search filters on location/date/type now work (columns exist in schema)
//   Bug 7 — event_id always comes from the typed parameter, never re-read from body

import '../main.dart';

class EventService {
  // ─────────────────────────────────────────────────────────
  // LIST all active events, newest first by event_date.
  // Joins admin profile for display name.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEvents() async {
    // No status filter here — RLS handles it:
    //   regular users: sees active only (policy: status = 'active')
    //   admins: sees all statuses (policy allows admin role)
    final data = await supabase
        .from('events')
        .select('*, admin:profiles!admin_id(full_name), driver:profiles!assigned_driver_id(full_name)')
        .order('event_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // SEARCH events by name, type, and/or date.
  // All three columns exist in the schema — this will NOT crash
  // (unlike the old Flask endpoint that filtered on phantom columns).
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> searchEvents({
    String? name,
    String? eventType,
    DateTime? fromDate,
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

    final data = await query.order('event_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // GET a single event's full details.
  // ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getEventDetails(int eventId) async {
    final data = await supabase
        .from('events')
        .select('*, admin:profiles!admin_id(full_name), driver:profiles!assigned_driver_id(full_name, id)')
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

    final adminId = supabase.auth.currentUser?.id;

    await supabase.from('events').insert({
      'name': name.trim(),
      'description': description?.trim(),
      'event_date': eventDate.toIso8601String(),
      'event_type': eventType?.trim(),
      'location_name': locationName?.trim(),
      'admin_id': adminId,
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
  }) async {
    final updates = <String, dynamic>{};
    if (name != null && name.trim().isNotEmpty) updates['name'] = name.trim();
    if (description != null) updates['description'] = description.trim();
    if (eventType != null) updates['event_type'] = eventType.trim();
    if (locationName != null) updates['location_name'] = locationName.trim();
    if (eventDate != null) {
      updates['event_date'] = eventDate.toIso8601String();
    }
    if (updates.isEmpty) return;

    await supabase.from('events').update(updates).eq('id', eventId);
  }

  // ─────────────────────────────────────────────────────────
  // GET ATTENDEES for an event (admin only).
  // RLS subs_select_admin ensures only the org admin can call this.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEventAttendees(
      int eventId) async {
    final data = await supabase
        .from('event_subscriptions')
        .select('user_id, profiles!user_id(full_name, phone)')
        .eq('event_id', eventId);
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // CANCEL an event (soft-delete via status flag). Admin-only.
  // ─────────────────────────────────────────────────────────
  static Future<void> cancelEvent(int eventId) async {
    await supabase
        .from('events')
        .update({'status': 'cancelled'})
        .eq('id', eventId);
  }

  // ─────────────────────────────────────────────────────────
  // SUBSCRIBE the current user to an event.
  //
  // Fix vs rover.py Bug 7: event_id comes ONLY from the
  // typed parameter — it is never re-read from a request body,
  // so there is no URL-vs-body mismatch.
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
  //
  // Fix vs rover.py Bug 4: old code wrote event.driver_id,
  // which does not exist. The correct column is assigned_driver_id.
  // ─────────────────────────────────────────────────────────
  static Future<void> assignDriver(int eventId, String driverUserId) async {
    await supabase
        .from('events')
        .update({'assigned_driver_id': driverUserId}) // correct column name
        .eq('id', eventId);
  }

  // ─────────────────────────────────────────────────────────
  // LIST all drivers (profiles with role = 'driver').
  // Used by the admin screen's driver-assignment dropdown.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getDrivers() async {
    final data = await supabase
        .from('profiles')
        .select('id, full_name, phone')
        .eq('role', 'driver')
        .order('full_name');
    return List<Map<String, dynamic>>.from(data);
  }

  // ─────────────────────────────────────────────────────────
  // LIST events assigned to the current driver.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getDriverEvents() async {
    final driverId = supabase.auth.currentUser?.id;
    if (driverId == null) return [];

    final data = await supabase
        .from('events')
        .select()
        .eq('assigned_driver_id', driverId)
        .eq('status', 'active')
        .order('event_date', ascending: true);
    return List<Map<String, dynamic>>.from(data);
  }
}
