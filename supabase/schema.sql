-- ═══════════════════════════════════════════════════════════════
-- ROVER — Supabase PostgreSQL Schema
-- Run this entire file in: Supabase Dashboard > SQL Editor
-- Requires: Database > Extensions > postgis (enable first)
-- ═══════════════════════════════════════════════════════════════

-- Enable PostGIS for geospatial queries
CREATE EXTENSION IF NOT EXISTS postgis;

-- ─────────────────────────────────────────────────────────────
-- PROFILES
-- Extends auth.users (managed by Supabase Auth).
-- One row per authenticated user; role determines app behaviour.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.profiles (
  id          uuid REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  role        text NOT NULL CHECK (role IN ('user', 'driver', 'admin')),
  full_name   text NOT NULL,
  phone       text,
  -- PostGIS geography point stored as (longitude, latitude), SRID 4326
  location    geography(POINT, 4326),
  -- FCM token for push notifications; updated after each login
  fcm_token   text,
  created_at  timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- EVENTS
-- Created by admins. Drivers are assigned per event.
-- location / location_name / event_date / event_type columns
-- exist here (they were MISSING from the old Flask model —
-- that omission caused the search endpoint to crash).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.events (
  id                  bigserial PRIMARY KEY,
  name                text NOT NULL,
  description         text,
  location            geography(POINT, 4326),
  location_name       text,
  event_date          timestamptz NOT NULL,
  event_type          text,
  admin_id            uuid REFERENCES public.profiles(id),
  -- Correct column name: assigned_driver_id
  -- (old code wrote to event.driver_id — wrong, caused silent failure)
  assigned_driver_id  uuid REFERENCES public.profiles(id),
  status              text DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'completed')),
  created_at          timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- EVENT SUBSCRIPTIONS
-- Many-to-many between users and events.
-- Unique constraint prevents duplicate subscriptions
-- (old code checked this manually with a query; the DB now
--  enforces it natively and returns a unique-violation error).
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.event_subscriptions (
  id          bigserial PRIMARY KEY,
  event_id    bigint REFERENCES public.events(id) ON DELETE CASCADE NOT NULL,
  user_id     uuid   REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  created_at  timestamptz DEFAULT now(),
  UNIQUE (event_id, user_id)
);

-- ─────────────────────────────────────────────────────────────
-- PICKUP REQUESTS
-- One row per user per event, holding their GPS pickup point,
-- the computed pickup order, and the ETA written by the
-- schedule-pickup Edge Function.
-- ─────────────────────────────────────────────────────────────
CREATE TABLE public.pickup_requests (
  id               bigserial PRIMARY KEY,
  event_id         bigint REFERENCES public.events(id) NOT NULL,
  user_id          uuid   REFERENCES public.profiles(id) NOT NULL,
  -- PostGIS point: INSERT as 'POINT(longitude latitude)'
  pickup_location  geography(POINT, 4326) NOT NULL,
  -- Set by schedule-pickup Edge Function (greedy nearest-neighbor)
  pickup_order     int,
  eta_minutes      int,
  status           text DEFAULT 'pending' CHECK (status IN ('pending', 'en_route', 'completed')),
  created_at       timestamptz DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- INDEXES
-- Foreign keys used in JOINs and WHERE filters.
-- ─────────────────────────────────────────────────────────────
CREATE INDEX ON public.event_subscriptions (event_id);
CREATE INDEX ON public.event_subscriptions (user_id);
CREATE INDEX ON public.pickup_requests (event_id);
CREATE INDEX ON public.pickup_requests (user_id);
CREATE INDEX ON public.events (admin_id);
CREATE INDEX ON public.events (assigned_driver_id);
CREATE INDEX ON public.events (status);
CREATE INDEX ON public.events (event_date);

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- Every table must have RLS enabled. This replaces the zero
-- auth middleware that existed in rover.py.
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.profiles           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pickup_requests    ENABLE ROW LEVEL SECURITY;

-- ── PROFILES ──────────────────────────────────────────────────
-- Anyone authenticated can read all profiles (needed for driver listing).
-- Users can only update their own row.
CREATE POLICY "profiles_select_all"
  ON public.profiles FOR SELECT
  USING (auth.uid() IS NOT NULL);

CREATE POLICY "profiles_insert_own"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- ── EVENTS ────────────────────────────────────────────────────
-- All authenticated users can read active events (powers the search screen).
-- Only admins can create, update, or cancel events.
CREATE POLICY "events_select_active"
  ON public.events FOR SELECT
  USING (status = 'active' AND auth.uid() IS NOT NULL);

CREATE POLICY "events_insert_admin"
  ON public.events FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "events_update_admin"
  ON public.events FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "events_delete_admin"
  ON public.events FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ── EVENT SUBSCRIPTIONS ───────────────────────────────────────
-- Users manage only their own subscriptions.
-- Admins can read all subscriptions (for organiser view).
CREATE POLICY "subs_select_own"
  ON public.event_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "subs_select_admin"
  ON public.event_subscriptions FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "subs_insert_own"
  ON public.event_subscriptions FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "subs_delete_own"
  ON public.event_subscriptions FOR DELETE
  USING (auth.uid() = user_id);

-- ── PICKUP REQUESTS ───────────────────────────────────────────
-- Users can read and insert their own requests.
-- Drivers can read ALL pickup requests (needed to compute routes).
-- Service role (used by Edge Function) bypasses RLS entirely.
CREATE POLICY "pickups_select_own"
  ON public.pickup_requests FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "pickups_select_driver"
  ON public.pickup_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'driver'
    )
  );

CREATE POLICY "pickups_insert_own"
  ON public.pickup_requests FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "pickups_update_own"
  ON public.pickup_requests FOR UPDATE
  USING (auth.uid() = user_id);

-- ═══════════════════════════════════════════════════════════════
-- HELPER: create the first admin account
-- Run this AFTER creating the user via Supabase Dashboard >
-- Authentication > Users > Invite User.
-- Replace <admin-user-uuid> with the UUID from that created user.
-- ═══════════════════════════════════════════════════════════════
-- INSERT INTO public.profiles (id, role, full_name)
-- VALUES ('<admin-user-uuid>', 'admin', 'Admin Name');
