// org_service.dart
//
// All organisation and invite management calls.
// Uses SECURITY DEFINER RPCs so that org creation,
// join-by-code and invite generation are all atomic and
// cannot be forged from the client.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';

class OrgService {
  // ─────────────────────────────────────────────────────────
  // CREATE ORGANISATION
  // The calling user becomes admin of the new org.
  // Returns the new org UUID.
  // ─────────────────────────────────────────────────────────
  static Future<String> createOrganisationAndAdmin({
    required String orgName,
    String? city,
    String? country,
    String orgType = 'church',
    String fullName = '',
  }) async {
    try {
      final result = await supabase.rpc(
        'create_organisation_and_admin',
        params: {
          'org_name':    orgName.trim(),
          'org_city':    city?.trim() ?? '',
          'org_country': country?.trim() ?? '',
          'org_type':    orgType,
          'p_full_name': fullName.trim(),
        },
      );
      return result as String;
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // JOIN ORGANISATION WITH INVITE CODE
  // Returns the role granted ('user' | 'driver').
  // ─────────────────────────────────────────────────────────
  static Future<String> joinWithCode({
    required String inviteCode,
    String fullName = '',
    String? phone,
  }) async {
    try {
      final result = await supabase.rpc(
        'join_organisation_with_code',
        params: {
          'invite_code': inviteCode.trim().toUpperCase(),
          'p_full_name': fullName.trim(),
          'p_phone':     phone?.trim() ?? '',
        },
      );
      return result as String;
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // GENERATE INVITE CODE
  // Admin only. Returns the new code string.
  // ─────────────────────────────────────────────────────────
  static Future<String> generateInviteCode({
    required String role,
    DateTime? expiresAt,
    int maxUses = 1,
  }) async {
    try {
      final result = await supabase.rpc(
        'generate_invite_code',
        params: {
          'p_role':       role,
          if (expiresAt != null) 'p_expires_at': expiresAt.toIso8601String(),
          'p_max_uses':   maxUses,
        },
      );
      return result as String;
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // GET MY ORGANISATION
  // ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getMyOrg() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final profile = await supabase
          .from('profiles')
          .select('org_id')
          .eq('id', userId)
          .single();

      final orgId = profile['org_id'] as String?;
      if (orgId == null) return null;

      final org = await supabase
          .from('organisations')
          .select()
          .eq('id', orgId)
          .single();

      return Map<String, dynamic>.from(org);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // GET ALL MEMBERS OF MY ORG
  // RLS limits results to same org automatically.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getOrgMembers() async {
    try {
      final data = await supabase
          .from('profiles')
          .select('id, full_name, role, phone, created_at')
          .order('role')
          .order('full_name');
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // GET ACTIVE INVITE CODES FOR MY ORG
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getOrgInvites() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return [];

      // Get org_id from profile
      final profile = await supabase
          .from('profiles')
          .select('org_id')
          .eq('id', userId)
          .single();

      final orgId = profile['org_id'] as String?;
      if (orgId == null) return [];

      final data = await supabase
          .from('org_invites')
          .select()
          .eq('org_id', orgId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // DEACTIVATE AN INVITE CODE
  // ─────────────────────────────────────────────────────────
  static Future<void> deactivateInvite(String inviteId) async {
    try {
      await supabase
          .from('org_invites')
          .update({'is_active': false})
          .eq('id', inviteId);
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // JOIN ORGANISATION WITH TOKEN
  // Replaces the invite-code mechanism for drivers and users.
  // p_token: UUID from rover.app/join/TOKEN deep link or QR scan.
  // p_role:  'user' | 'driver' — chosen on the welcome screen.
  // Returns the role that was set.
  // ─────────────────────────────────────────────────────────
  static Future<String> joinOrganisation({
    required String token,
    String role = 'user',
  }) async {
    try {
      final result = await supabase.rpc(
        'join_organisation',
        params: {
          'p_token': token.trim(),
          'p_role':  role,
        },
      );
      return result as String;
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // GET ORG FROM TOKEN
  // Public lookup — called before auth to resolve the org name
  // shown in the WelcomePage / RegisterPage banner.
  // Returns null if the token is invalid.
  // ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getOrgFromToken(String token) async {
    try {
      final rows = await supabase.rpc(
        'get_org_from_token',
        params: {'p_token': token.trim()},
      ) as List<dynamic>;
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first as Map);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  // RESET ORG TOKEN
  // Generates a new UUID token, invalidating all existing QR
  // codes and share links. Admin-only; enforced by RPC.
  // Returns the new token as a string.
  // ─────────────────────────────────────────────────────────
  static Future<String> resetOrgToken(String orgId) async {
    try {
      final result = await supabase.rpc(
        'reset_org_token',
        params: {'p_org_id': orgId},
      );
      return result as String;
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // SEARCH ORGANISATIONS
  // Returns orgs where searchable = true and name/city matches
  // query. Used by the search fallback on the join screen.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> searchOrgs(String query) async {
    try {
      final q = query.trim();
      if (q.isEmpty) return [];
      // Uses a SECURITY DEFINER RPC so the query is parameterised
      // server-side — no string interpolation in the filter.
      final data = await supabase.rpc(
        'search_organisations',
        params: {'p_query': q},
      ) as List<dynamic>;
      return List<Map<String, dynamic>>.from(
        data.map((e) => Map<String, dynamic>.from(e as Map)),
      );
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // REQUEST TO JOIN AN ORG (search fallback)
  // Inserts a pending request; admin approves from Share tab.
  // ─────────────────────────────────────────────────────────
  static Future<void> requestToJoin(String orgId) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('You must be signed in.');
      await supabase.from('org_join_requests').insert({
        'org_id':  orgId,
        'user_id': userId,
      });
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // GET PENDING JOIN REQUESTS FOR MY ORG (admin only)
  //
  // Fix M-12: org_join_requests.user_id has a FK to auth.users, not
  // profiles, so PostgREST cannot resolve 'profiles!user_id' from
  // org_join_requests directly. We use a two-step fetch instead:
  //   1. Fetch pending request rows (RLS scopes to admin's org).
  //   2. Batch-fetch profiles by id IN (user_ids).
  // This correctly uses profiles.id = auth.users.id = user_id.
  // ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPendingRequests() async {
    try {
      final requests = await supabase
          .from('org_join_requests')
          .select('id, user_id, created_at')
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      final list = List<Map<String, dynamic>>.from(requests);
      if (list.isEmpty) return [];

      // Batch-fetch profiles whose id matches the requesting user_ids
      final userIds = list.map((r) => r['user_id'] as String).toList();
      final profiles = await supabase
          .from('profiles')
          .select('id, full_name, phone')
          .inFilter('id', userIds);

      final profileMap = <String, Map<String, dynamic>>{
        for (final p in List<Map<String, dynamic>>.from(profiles))
          p['id'] as String: p,
      };

      // Merge profile data into each request row under the 'profiles' key
      // so existing UI code that reads r['profiles']['full_name'] still works.
      return list.map((r) {
        final profile = profileMap[r['user_id'] as String];
        return {...r, 'profiles': profile};
      }).toList();
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // APPROVE A JOIN REQUEST (admin only)
  // Calls the SECURITY DEFINER RPC so the admin can set org_id
  // on a profile row they don't otherwise own.
  // ─────────────────────────────────────────────────────────
  static Future<void> approveRequest(int requestId) async {
    try {
      await supabase.rpc(
        'approve_join_request',
        params: {'p_request_id': requestId},
      );
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // REJECT A JOIN REQUEST (admin only)
  // ─────────────────────────────────────────────────────────
  static Future<void> rejectRequest(int requestId) async {
    try {
      await supabase.rpc(
        'reject_join_request',
        params: {'p_request_id': requestId},
      );
    } catch (e) {
      throw Exception(_clean(e));
    }
  }

  // ─────────────────────────────────────────────────────────
  // REALTIME — pending join requests for admin's org (M-9)
  // Returns a RealtimeChannel that fires onChange on any
  // INSERT / UPDATE / DELETE to org_join_requests for orgId.
  // Caller must call .unsubscribe() on dispose.
  // ─────────────────────────────────────────────────────────
  static RealtimeChannel subscribeToPendingRequests({
    required String orgId,
    required void Function() onChange,
  }) {
    return supabase
        .channel('pending_requests_$orgId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'org_join_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'org_id',
            value: orgId,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  // ── Private ───────────────────────────────────────────────
  static String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
}
