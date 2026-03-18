-- ═══════════════════════════════════════════════════════════════
-- ROVER — Supabase PostgreSQL Schema  (multi-tenant, v2)
--
-- Run the ENTIRE file in: Supabase Dashboard > SQL Editor
-- Safe to re-run: uses IF NOT EXISTS / OR REPLACE / DROP IF EXISTS
--
-- Prerequisites:
--   1. Database > Extensions > Enable "postgis"
--   2. Database > Extensions > Enable "uuid-ossp" (for gen_random_uuid)
-- ═══════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ─────────────────────────────────────────────────────────────
-- ORGANISATIONS
-- The tenant boundary. Every user, event, driver and pickup
-- belongs to exactly one organisation.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.organisations (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text NOT NULL,
  city       text,
  country    text,
  org_type   text NOT NULL DEFAULT 'church'
             CHECK (org_type IN ('church','conference','corporate','school','other')),
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- PROFILES
-- One row per auth.users entry. org_id is NULL until the user
-- completes organisation setup (create or join).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id         uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role       text NOT NULL DEFAULT 'user'
             CHECK (role IN ('user','driver','admin')),
  full_name  text NOT NULL DEFAULT '',
  phone      text,
  org_id     uuid REFERENCES public.organisations(id),
  location   geography(POINT, 4326),
  fcm_token  text,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- ORG INVITES
-- Admins generate codes; drivers/members use them to join.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.org_invites (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  org_id     uuid NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  code       text NOT NULL UNIQUE,
  role       text NOT NULL CHECK (role IN ('user','driver')),
  created_by uuid REFERENCES public.profiles(id),
  expires_at timestamptz,
  max_uses   int  NOT NULL DEFAULT 1,
  use_count  int  NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- EVENTS
-- Created by admins. org_id and admin_id are set automatically
-- by the before-insert trigger (cannot be forged by clients).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.events (
  id                 bigserial PRIMARY KEY,
  org_id             uuid REFERENCES public.organisations(id),
  name               text NOT NULL,
  description        text,
  location           geography(POINT, 4326),
  location_name      text,
  event_date         timestamptz NOT NULL,
  event_type         text,
  admin_id           uuid REFERENCES public.profiles(id),
  assigned_driver_id uuid REFERENCES public.profiles(id),
  status             text NOT NULL DEFAULT 'active'
                     CHECK (status IN ('active','cancelled','completed')),
  created_at         timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- EVENT SUBSCRIPTIONS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.event_subscriptions (
  id         bigserial PRIMARY KEY,
  event_id   bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id    uuid   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE (event_id, user_id)
);

-- ─────────────────────────────────────────────────────────────
-- PICKUP REQUESTS
-- ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pickup_requests (
  id              bigserial PRIMARY KEY,
  event_id        bigint NOT NULL REFERENCES public.events(id),
  user_id         uuid   NOT NULL REFERENCES public.profiles(id),
  pickup_location geography(POINT, 4326) NOT NULL,
  pickup_order    int,
  eta_minutes     int,
  status          text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','en_route','completed')),
  created_at      timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- IDEMPOTENT CONSTRAINT ADDITIONS
-- Enforce event_date is not in the past at the DB layer.
-- A 1-hour grace window tolerates minor clock skew between client
-- and server when saving events that start "right now".
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS events_date_not_past;
ALTER TABLE public.events
  ADD CONSTRAINT events_date_not_past
    CHECK (event_date > now() - interval '1 hour');

-- ─────────────────────────────────────────────────────────────
-- IDEMPOTENT COLUMN ADDITIONS
-- Safe to re-run: no-ops if columns already exist.
-- Required for databases with pre-existing tables from older
-- schema versions that lacked these columns.
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS org_id     uuid REFERENCES public.organisations(id),
  ADD COLUMN IF NOT EXISTS location   geography(POINT, 4326),
  ADD COLUMN IF NOT EXISTS fcm_token  text;

ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS org_id             uuid REFERENCES public.organisations(id),
  ADD COLUMN IF NOT EXISTS admin_id           uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS assigned_driver_id uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS location_name      text,
  ADD COLUMN IF NOT EXISTS event_type         text;

-- ─────────────────────────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_profiles_org        ON public.profiles          (org_id);
CREATE INDEX IF NOT EXISTS idx_events_org          ON public.events            (org_id);
CREATE INDEX IF NOT EXISTS idx_events_status       ON public.events            (status);
CREATE INDEX IF NOT EXISTS idx_events_date         ON public.events            (event_date);
CREATE INDEX IF NOT EXISTS idx_events_driver       ON public.events            (assigned_driver_id);
CREATE INDEX IF NOT EXISTS idx_subs_event          ON public.event_subscriptions (event_id);
CREATE INDEX IF NOT EXISTS idx_subs_user           ON public.event_subscriptions (user_id);
CREATE INDEX IF NOT EXISTS idx_pickups_event       ON public.pickup_requests   (event_id);
CREATE INDEX IF NOT EXISTS idx_pickups_user        ON public.pickup_requests   (user_id);
CREATE INDEX IF NOT EXISTS idx_invites_org         ON public.org_invites       (org_id);
CREATE INDEX IF NOT EXISTS idx_invites_code        ON public.org_invites       (code);

-- ═══════════════════════════════════════════════════════════════
-- SECURITY DEFINER HELPERS
--
-- These two functions break the RLS-on-profiles recursion:
-- if policies on profiles used "EXISTS (SELECT 1 FROM profiles …)"
-- PostgreSQL would recurse infinitely. SECURITY DEFINER means the
-- function runs as its owner (postgres), bypassing RLS internally.
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_my_org_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT org_id FROM public.profiles WHERE id = auth.uid()
$$;

CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid()
$$;

-- ═══════════════════════════════════════════════════════════════
-- RPC: CREATE ORGANISATION + CLAIM ADMIN ROLE  (atomic)
--
-- Called from the Flutter app immediately after a successful
-- signUp (or after a login that returns 'no_org').
-- The calling user already has a profile row (created by the
-- handle_new_user trigger). This function creates the org and
-- upserts the profile with the correct org_id and role.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.create_organisation_and_admin(
  org_name    text,
  org_city    text    DEFAULT NULL,
  org_country text    DEFAULT NULL,
  org_type    text    DEFAULT 'church',
  p_full_name text    DEFAULT ''
)
RETURNS uuid   -- new org_id
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  new_org_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;

  IF trim(org_name) = '' THEN
    RAISE EXCEPTION 'Organisation name is required.';
  END IF;

  IF org_type NOT IN ('church','conference','corporate','school','other') THEN
    RAISE EXCEPTION 'Invalid organisation type.';
  END IF;

  -- Create the organisation
  INSERT INTO public.organisations (name, city, country, org_type)
  VALUES (
    trim(org_name),
    NULLIF(trim(COALESCE(org_city, '')), ''),
    NULLIF(trim(COALESCE(org_country, '')), ''),
    org_type
  )
  RETURNING id INTO new_org_id;

  -- Link the caller to this org as admin
  INSERT INTO public.profiles (id, role, full_name, org_id)
  VALUES (auth.uid(), 'admin', trim(COALESCE(p_full_name, '')), new_org_id)
  ON CONFLICT (id) DO UPDATE
    SET role      = 'admin',
        full_name = CASE WHEN trim(EXCLUDED.full_name) <> '' THEN trim(EXCLUDED.full_name)
                         ELSE public.profiles.full_name END,
        org_id    = new_org_id;

  RETURN new_org_id;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- RPC: JOIN ORGANISATION WITH INVITE CODE  (atomic)
--
-- Validates the code, increments its use count (with row-level
-- lock to prevent race conditions), and upserts the profile.
-- Returns the role string ('driver' | 'user').
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.join_organisation_with_code(
  invite_code text,
  p_full_name text   DEFAULT '',
  p_phone     text   DEFAULT NULL
)
RETURNS text  -- role granted
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  inv     public.org_invites%ROWTYPE;
  granted text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;

  -- Lock the invite row to serialise concurrent joins
  SELECT * INTO inv
  FROM   public.org_invites
  WHERE  code        = upper(trim(invite_code))
    AND  is_active   = true
    AND  (expires_at IS NULL OR expires_at > now())
    AND  use_count   < max_uses
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite code. Ask your administrator for a new one.';
  END IF;

  granted := inv.role;

  -- Increment use count; deactivate when exhausted
  UPDATE public.org_invites
  SET    use_count  = use_count + 1,
         is_active  = (use_count + 1 < max_uses)
  WHERE  id = inv.id;

  -- Link caller to org with the role from the invite
  INSERT INTO public.profiles (id, role, full_name, org_id, phone)
  VALUES (
    auth.uid(),
    granted,
    trim(COALESCE(p_full_name, '')),
    inv.org_id,
    NULLIF(trim(COALESCE(p_phone, '')), '')
  )
  ON CONFLICT (id) DO UPDATE
    SET role      = granted,
        full_name = CASE WHEN trim(EXCLUDED.full_name) <> '' THEN trim(EXCLUDED.full_name)
                         ELSE public.profiles.full_name END,
        org_id    = inv.org_id,
        phone     = COALESCE(NULLIF(trim(COALESCE(p_phone, '')), ''), public.profiles.phone);

  RETURN granted;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- RPC: GENERATE INVITE CODE
--
-- Admins call this to produce a shareable code.
-- The code is 8 characters, uppercase alphanumeric, unique.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.generate_invite_code(
  p_role        text,
  p_expires_at  timestamptz DEFAULT NULL,
  p_max_uses    int         DEFAULT 1
)
RETURNS text  -- the generated code
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  admin_org_id uuid;
  new_code     text;
BEGIN
  IF p_role NOT IN ('driver', 'user') THEN
    RAISE EXCEPTION 'Role must be ''driver'' or ''user''.';
  END IF;

  -- Verify caller is an admin of some org
  SELECT org_id INTO admin_org_id
  FROM   public.profiles
  WHERE  id = auth.uid() AND role = 'admin';

  IF admin_org_id IS NULL THEN
    RAISE EXCEPTION 'Only organisation admins can generate invite codes.';
  END IF;

  IF p_max_uses < 1 THEN
    RAISE EXCEPTION 'max_uses must be at least 1.';
  END IF;

  -- Generate a unique 8-char code
  LOOP
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.org_invites WHERE code = new_code);
  END LOOP;

  INSERT INTO public.org_invites (org_id, code, role, created_by, expires_at, max_uses)
  VALUES (admin_org_id, new_code, p_role, auth.uid(), p_expires_at, p_max_uses);

  RETURN new_code;
END;
$$;

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER: auto-set org_id + admin_id on new events
--
-- Reads the inserting user's org from their profile (SECURITY
-- DEFINER so it bypasses RLS). This prevents clients from ever
-- cross-posting an event to another organisation.
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_event_defaults()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  NEW.admin_id := auth.uid();
  NEW.org_id   := (SELECT org_id FROM public.profiles WHERE id = auth.uid());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_event_insert ON public.events;
CREATE TRIGGER before_event_insert
  BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE PROCEDURE public.set_event_defaults();

-- ═══════════════════════════════════════════════════════════════
-- TRIGGER: auto-create profile row on new auth signup
--
-- org_id is deliberately NOT set here — it stays NULL until the
-- user completes org setup via create_organisation_and_admin()
-- or join_organisation_with_code().
-- ═══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (
    NEW.id,
    'user',  -- placeholder; RPCs set the real role
    COALESCE(NEW.raw_user_meta_data->>'full_name', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY — Enable on all tables
-- ═══════════════════════════════════════════════════════════════
ALTER TABLE public.organisations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_invites         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pickup_requests     ENABLE ROW LEVEL SECURITY;

-- ── Drop all existing policies before recreating ──────────────
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I',
                   r.policyname, r.schemaname, r.tablename);
  END LOOP;
END$$;

-- ── ORGANISATIONS ─────────────────────────────────────────────
-- Members can read their own org only.
-- Only SECURITY DEFINER RPCs can INSERT.
-- Admin can update their org's details.

CREATE POLICY "orgs_select_own"
  ON public.organisations FOR SELECT
  USING (id = public.get_my_org_id());

CREATE POLICY "orgs_update_admin"
  ON public.organisations FOR UPDATE
  USING (id = public.get_my_org_id() AND public.get_my_role() = 'admin');

-- ── PROFILES ──────────────────────────────────────────────────
-- Members can read their own profile plus all profiles in their org.
-- Everyone can only INSERT/UPDATE their own row.

CREATE POLICY "profiles_select"
  ON public.profiles FOR SELECT
  USING (
    auth.uid() IS NOT NULL AND (
      id = auth.uid()
      OR org_id = public.get_my_org_id()
    )
  );

CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- ── ORG INVITES ───────────────────────────────────────────────
-- Only admins can read their org's invite codes.
-- All inserts/updates go through SECURITY DEFINER RPCs.

CREATE POLICY "invites_select_admin"
  ON public.org_invites FOR SELECT
  USING (
    org_id = public.get_my_org_id()
    AND public.get_my_role() = 'admin'
  );

-- ── EVENTS ────────────────────────────────────────────────────
-- Regular users/drivers see active events in their org only.
-- Admins see all statuses (active + cancelled + completed) in their org.
-- Inserts, updates and deletes restricted to admins of the same org.

CREATE POLICY "events_select"
  ON public.events FOR SELECT
  USING (
    auth.uid() IS NOT NULL
    AND org_id = public.get_my_org_id()
    AND (
      status = 'active'
      OR public.get_my_role() = 'admin'
    )
  );

CREATE POLICY "events_insert_admin"
  ON public.events FOR INSERT
  WITH CHECK (
    public.get_my_role() = 'admin'
    -- org_id is set by trigger; the policy just verifies role
  );

CREATE POLICY "events_update_admin"
  ON public.events FOR UPDATE
  USING (
    public.get_my_role() = 'admin'
    AND org_id = public.get_my_org_id()
  );

CREATE POLICY "events_delete_admin"
  ON public.events FOR DELETE
  USING (
    public.get_my_role() = 'admin'
    AND org_id = public.get_my_org_id()
  );

-- ── EVENT SUBSCRIPTIONS ───────────────────────────────────────
-- Users manage only their own subscriptions.
-- Admins can read all subscriptions for events in their org.

CREATE POLICY "subs_select_own"
  ON public.event_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "subs_select_admin"
  ON public.event_subscriptions FOR SELECT
  USING (
    public.get_my_role() = 'admin'
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.org_id = public.get_my_org_id()
    )
  );

CREATE POLICY "subs_insert_own"
  ON public.event_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "subs_delete_own"
  ON public.event_subscriptions FOR DELETE
  USING (auth.uid() = user_id);

-- ── PICKUP REQUESTS ───────────────────────────────────────────
-- Users can read/insert/update their own requests.
-- Drivers can read all requests for events assigned to them.
-- Edge Function uses service role (bypasses RLS) for route writes.

CREATE POLICY "pickups_select_own"
  ON public.pickup_requests FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "pickups_select_driver"
  ON public.pickup_requests FOR SELECT
  USING (
    public.get_my_role() = 'driver'
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.assigned_driver_id = auth.uid()
    )
  );

CREATE POLICY "pickups_insert_own"
  ON public.pickup_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "pickups_update_own"
  ON public.pickup_requests FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "pickups_update_driver"
  ON public.pickup_requests FOR UPDATE
  USING (
    public.get_my_role() = 'driver'
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.assigned_driver_id = auth.uid()
    )
  );
