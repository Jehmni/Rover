-- Rover schema v7: profile security hardening
--
-- Purpose:
-- Prevent authenticated users from self-escalating role/org membership
-- via direct updates to public.profiles.
--
-- Safe to re-run.

BEGIN;

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role = public.get_my_role()
    AND org_id IS NOT DISTINCT FROM public.get_my_org_id()
  );

COMMIT;
