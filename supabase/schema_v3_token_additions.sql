-- ============================================================
-- Schema v3 additions: org_token and token-based join RPCs
-- Run this in Supabase SQL Editor AFTER schema.sql
-- ============================================================

-- 1. Add org_token to organisations
--    Each org gets a unique UUID that powers its invite QR / link.
ALTER TABLE public.organisations
  ADD COLUMN IF NOT EXISTS org_token UUID DEFAULT gen_random_uuid() UNIQUE NOT NULL;

-- Backfill any existing rows (safe no-op if already populated).
UPDATE public.organisations SET org_token = gen_random_uuid() WHERE org_token IS NULL;

-- ─────────────────────────────────────────────────────────────
-- 2. join_organisation(p_token, p_role)
--
--    Called when a new user enters/scans the org token on
--    OrgSetupPage. Sets org_id and role on the caller's profile.
--
--    p_role: 'user' | 'driver'  — determined by the card tapped.
--    Returns the role that was set.
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
  v_org_id UUID;
BEGIN
  IF p_role NOT IN ('user', 'driver') THEN
    RAISE EXCEPTION 'Invalid role. Must be user or driver.';
  END IF;

  SELECT id INTO v_org_id
  FROM public.organisations
  WHERE org_token = p_token;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite link. Ask your administrator to share a new one.';
  END IF;

  UPDATE public.profiles
  SET org_id = v_org_id,
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
-- 3. reset_org_token(p_org_id)
--
--    Generates a new random token, invalidating all existing
--    QR codes and share links. Admin-only.
--    Returns the new token UUID.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.reset_org_token(p_org_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_token UUID;
BEGIN
  IF get_my_role() != 'admin' OR get_my_org_id() != p_org_id THEN
    RAISE EXCEPTION 'Only the organisation admin can reset the invite link.';
  END IF;

  v_new_token := gen_random_uuid();
  UPDATE public.organisations SET org_token = v_new_token WHERE id = p_org_id;
  RETURN v_new_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reset_org_token(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────
-- 4. get_org_from_token(p_token)
--
--    Public lookup — returns org name and type for the welcome
--    banner before the user has signed in.
--    Granted to anon so it works without a session.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_org_from_token(p_token UUID)
RETURNS TABLE(id UUID, name TEXT, org_type TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
    SELECT o.id, o.name, o.org_type
    FROM public.organisations o
    WHERE o.org_token = p_token;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_org_from_token(UUID) TO anon, authenticated;
