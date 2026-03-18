-- ============================================================
-- Schema v5: server-side org search RPC
--
-- Replaces the client-side PostgREST .or('name.ilike…,city.ilike…')
-- filter in OrgService.searchOrgs() with a SECURITY DEFINER function.
--
-- Benefits:
--   - Removes string-interpolation filter injection surface
--   - Centralises search logic for future rate-limiting or ranking
--   - Grants to anon so pre-auth users (join flow) can search
--
-- Run in Supabase SQL Editor AFTER schema_v4_conference_search.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.search_organisations(p_query TEXT)
RETURNS TABLE (
  id        UUID,
  name      TEXT,
  city      TEXT,
  org_type  TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pattern TEXT;
BEGIN
  v_pattern := '%' || trim(p_query) || '%';

  RETURN QUERY
    SELECT o.id, o.name, o.city, o.org_type
    FROM   public.organisations o
    WHERE  o.searchable = true
      AND  (o.name ILIKE v_pattern OR o.city ILIKE v_pattern)
    ORDER  BY o.name
    LIMIT  20;
END;
$$;

-- Allow both unauthenticated users (join flow before sign-up)
-- and authenticated users to call this function.
GRANT EXECUTE ON FUNCTION public.search_organisations(TEXT) TO anon, authenticated;
