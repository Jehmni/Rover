-- schema_v6_fixes.sql
-- Applies all fixes identified in the Phase B audit.
-- Safe to run multiple times (idempotent).
-- Run AFTER schema_v4_conference_search.sql and schema_v5_search_rpc.sql.
--
-- Changes:
--   1. UNIQUE constraint on pickup_requests(event_id, user_id)       — H-3
--   2. Index on organisations.org_token                               — M-7
--   3. Admin SELECT policy on pickup_requests                         — L-8
--   4. Index on org_join_requests(status) for pending request queries
-- ─────────────────────────────────────────────────────────────────────────

-- ── 1. UNIQUE constraint on pickup_requests (event_id, user_id) ─────────
-- Prevents TOCTOU race-condition duplicates when user double-taps.
-- A user can only have ONE row per event (regardless of status).
-- The client-side duplicate check remains as a UX guard; this is the
-- server-side guarantee.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'pickup_requests_event_user_unique'
      AND conrelid = 'public.pickup_requests'::regclass
  ) THEN
    ALTER TABLE public.pickup_requests
      ADD CONSTRAINT pickup_requests_event_user_unique UNIQUE (event_id, user_id);
  END IF;
END $$;

-- ── 2. Index on organisations.org_token ─────────────────────────────────
-- Every QR scan, deep link join, and org resolution query filters on
-- org_token. Without this index the DB does a full sequential scan.
CREATE INDEX IF NOT EXISTS idx_organisations_org_token
  ON public.organisations (org_token);

-- ── 3. Index on org_join_requests.status ────────────────────────────────
-- getPendingRequests() always filters WHERE status = 'pending'.
CREATE INDEX IF NOT EXISTS idx_org_join_requests_status
  ON public.org_join_requests (status);

-- ── 4. Admin SELECT policy on pickup_requests ───────────────────────────
-- Without this policy, admins cannot see pickup data for events in their
-- own org (needed for future admin monitoring views).
DROP POLICY IF EXISTS "pickups_select_admin" ON public.pickup_requests;
CREATE POLICY "pickups_select_admin"
  ON public.pickup_requests
  FOR SELECT
  TO authenticated
  USING (
    public.get_my_role() = 'admin'
    AND event_id IN (
      SELECT id FROM public.events
      WHERE org_id = public.get_my_org_id()
    )
  );

-- ── 5. Driver UPDATE policy on pickup_requests ──────────────────────────
-- Allows the assigned driver to update pickup_order, eta_minutes, and
-- status on pickups for their assigned events (en_route, completed).
-- The Edge Function uses service-role and bypasses RLS; this policy
-- covers the direct client call for status transitions.
DROP POLICY IF EXISTS "pickups_update_driver" ON public.pickup_requests;
CREATE POLICY "pickups_update_driver"
  ON public.pickup_requests
  FOR UPDATE
  TO authenticated
  USING (
    public.get_my_role() = 'driver'
    AND event_id IN (
      SELECT id FROM public.events
      WHERE assigned_driver_id = auth.uid()
        AND org_id = public.get_my_org_id()
    )
  )
  WITH CHECK (
    public.get_my_role() = 'driver'
    AND event_id IN (
      SELECT id FROM public.events
      WHERE assigned_driver_id = auth.uid()
        AND org_id = public.get_my_org_id()
    )
  );
