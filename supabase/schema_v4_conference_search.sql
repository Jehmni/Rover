-- ============================================================
-- Schema v4 additions: conference orgs, email allowlist,
-- join requests (search fallback), org search support.
-- Run in Supabase SQL Editor AFTER schema_v3_token_additions.sql
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. searchable flag on organisations
--    Community orgs: searchable = true  (discoverable in search)
--    Conference orgs: searchable = false (hidden by default)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.organisations
  ADD COLUMN IF NOT EXISTS searchable BOOLEAN NOT NULL DEFAULT true;

-- Allow any authenticated user to SELECT searchable orgs
-- (needed so users without an org_id can run the search flow)
DROP POLICY IF EXISTS "orgs_search_select" ON public.organisations;
CREATE POLICY "orgs_search_select" ON public.organisations
  FOR SELECT USING (searchable = true);

-- ─────────────────────────────────────────────────────────────
-- 2. org_email_allowlist
--    Conference orgs can upload a list of permitted emails.
--    join_organisation() checks this list before granting access.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.org_email_allowlist (
  id         BIGSERIAL PRIMARY KEY,
  org_id     UUID NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  email      TEXT NOT NULL,
  claimed    BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(org_id, email)
);

ALTER TABLE public.org_email_allowlist ENABLE ROW LEVEL SECURITY;

-- Only the admin of the org may manage the allowlist
DROP POLICY IF EXISTS "allowlist_admin" ON public.org_email_allowlist;
CREATE POLICY "allowlist_admin" ON public.org_email_allowlist
  FOR ALL USING (
    get_my_role() = 'admin' AND org_id = get_my_org_id()
  );

-- ─────────────────────────────────────────────────────────────
-- 3. org_join_requests
--    Search fallback: users who don't have a link request to
--    join an org. Admin approves or rejects from the Share tab.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.org_join_requests (
  id         BIGSERIAL PRIMARY KEY,
  org_id     UUID NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status     TEXT NOT NULL DEFAULT 'pending'
             CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(org_id, user_id)
);

ALTER TABLE public.org_join_requests ENABLE ROW LEVEL SECURITY;

-- Users can see and insert their own requests
DROP POLICY IF EXISTS "requests_own_select" ON public.org_join_requests;
CREATE POLICY "requests_own_select" ON public.org_join_requests
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "requests_own_insert" ON public.org_join_requests;
CREATE POLICY "requests_own_insert" ON public.org_join_requests
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Admins can see and update requests for their org
DROP POLICY IF EXISTS "requests_admin_select" ON public.org_join_requests;
CREATE POLICY "requests_admin_select" ON public.org_join_requests
  FOR SELECT USING (
    get_my_role() = 'admin' AND org_id = get_my_org_id()
  );

DROP POLICY IF EXISTS "requests_admin_update" ON public.org_join_requests;
CREATE POLICY "requests_admin_update" ON public.org_join_requests
  FOR UPDATE USING (
    get_my_role() = 'admin' AND org_id = get_my_org_id()
  );

-- ─────────────────────────────────────────────────────────────
-- 4. Updated join_organisation — adds conference allowlist check
--    Replaces the version from schema_v3_token_additions.sql.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.join_organisation(
  p_token UUID,
  p_role  TEXT DEFAULT 'user'
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org   public.organisations%ROWTYPE;
  v_email TEXT;
BEGIN
  IF p_role NOT IN ('user', 'driver') THEN
    RAISE EXCEPTION 'Invalid role. Must be user or driver.';
  END IF;

  SELECT * INTO v_org FROM public.organisations WHERE org_token = p_token;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite link. Ask your administrator to share a new one.';
  END IF;

  -- Conference orgs with an allowlist: verify caller's email before joining
  IF v_org.org_type = 'conference' THEN
    v_email := (SELECT email FROM auth.users WHERE id = auth.uid());

    IF EXISTS (
      SELECT 1 FROM public.org_email_allowlist WHERE org_id = v_org.id LIMIT 1
    ) THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.org_email_allowlist
        WHERE org_id = v_org.id AND email = v_email AND claimed = false
      ) THEN
        RAISE EXCEPTION
          'Your email is not on the attendee list for this event. '
          'Contact the organiser if you believe this is a mistake.';
      END IF;
      -- Mark the email slot as claimed so it cannot be reused
      UPDATE public.org_email_allowlist
        SET claimed = true
        WHERE org_id = v_org.id AND email = v_email;
    END IF;
  END IF;

  UPDATE public.profiles
  SET org_id = v_org.id,
      role   = p_role
  WHERE id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profile not found. Please register first.';
  END IF;

  RETURN p_role;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_organisation(UUID, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 5. approve_join_request(p_request_id)
--    Admin-only. Sets org_id on the user's profile.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.approve_join_request(p_request_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req public.org_join_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM public.org_join_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found.'; END IF;

  IF get_my_role() != 'admin' OR get_my_org_id() != v_req.org_id THEN
    RAISE EXCEPTION 'Only the organisation admin can approve requests.';
  END IF;

  UPDATE public.org_join_requests SET status = 'approved' WHERE id = p_request_id;

  -- Set org_id on user's profile (role was already set during registration)
  UPDATE public.profiles SET org_id = v_req.org_id WHERE id = v_req.user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_join_request(BIGINT) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 6. reject_join_request(p_request_id)
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reject_join_request(p_request_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req public.org_join_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_req FROM public.org_join_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Request not found.'; END IF;

  IF get_my_role() != 'admin' OR get_my_org_id() != v_req.org_id THEN
    RAISE EXCEPTION 'Only the organisation admin can reject requests.';
  END IF;

  UPDATE public.org_join_requests SET status = 'rejected' WHERE id = p_request_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_join_request(BIGINT) TO authenticated;
