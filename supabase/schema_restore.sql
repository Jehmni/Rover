-- ═══════════════════════════════════════════════════════════════
-- ROVER — Full Schema Restore Script
--
-- PURPOSE: Restore the database to the correct state as defined
--          by schema.sql + v3 + v4 + v5 + v6 + v7 additions.
--          Safe to run on a database in any broken/partial state.
--          Every statement is idempotent (DROP IF EXISTS, OR REPLACE,
--          ADD COLUMN IF NOT EXISTS, etc.).
--
-- Run this entire file in Supabase Dashboard → SQL Editor.
-- ═══════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────
-- 0. EXTENSIONS
-- ─────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ─────────────────────────────────────────────────────────────
-- 1. TABLES  (IF NOT EXISTS — preserves existing data)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.organisations (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name       text NOT NULL,
  city       text,
  country    text,
  org_type   text NOT NULL DEFAULT 'church'
             CHECK (org_type IN ('church','conference','corporate','school','other')),
  join_policy text NOT NULL DEFAULT 'open'
             CHECK (join_policy IN ('open','approval','allowlist')),
  driver_join_policy text NOT NULL DEFAULT 'approval'
             CHECK (driver_join_policy IN ('approval','open')),
  created_at timestamptz DEFAULT now()
);

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

CREATE TABLE IF NOT EXISTS public.event_subscriptions (
  id         bigserial PRIMARY KEY,
  event_id   bigint NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  user_id    uuid   NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now(),
  UNIQUE (event_id, user_id)
);

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

CREATE TABLE IF NOT EXISTS public.org_email_allowlist (
  id         BIGSERIAL PRIMARY KEY,
  org_id     UUID NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  email      TEXT NOT NULL,
  claimed    BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(org_id, email)
);

CREATE TABLE IF NOT EXISTS public.org_join_requests (
  id         BIGSERIAL PRIMARY KEY,
  org_id     UUID NOT NULL REFERENCES public.organisations(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_role TEXT NOT NULL DEFAULT 'user'
             CHECK (requested_role IN ('user', 'driver')),
  status     TEXT NOT NULL DEFAULT 'pending'
             CHECK (status IN ('pending', 'approved', 'rejected')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(org_id, user_id)
);


-- ─────────────────────────────────────────────────────────────
-- 2. IDEMPOTENT COLUMN ADDITIONS
--    No-ops if the columns already exist.
-- ─────────────────────────────────────────────────────────────

-- profiles — columns added in v2
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS org_id     uuid REFERENCES public.organisations(id),
  ADD COLUMN IF NOT EXISTS location   geography(POINT, 4326),
  ADD COLUMN IF NOT EXISTS fcm_token  text;

-- events — columns added in v2
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS org_id             uuid REFERENCES public.organisations(id),
  ADD COLUMN IF NOT EXISTS admin_id           uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS assigned_driver_id uuid REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS location_name      text,
  ADD COLUMN IF NOT EXISTS event_type         text;

-- organisations — column added in v3
ALTER TABLE public.organisations
  ADD COLUMN IF NOT EXISTS org_token UUID DEFAULT gen_random_uuid() UNIQUE NOT NULL;

-- Backfill any rows that somehow have a NULL token
UPDATE public.organisations SET org_token = gen_random_uuid() WHERE org_token IS NULL;

-- organisations — column added in v4
ALTER TABLE public.organisations
  ADD COLUMN IF NOT EXISTS searchable BOOLEAN NOT NULL DEFAULT true;

-- organisations — access control settings
ALTER TABLE public.organisations
  ADD COLUMN IF NOT EXISTS join_policy text NOT NULL DEFAULT 'open'
    CHECK (join_policy IN ('open','approval','allowlist')),
  ADD COLUMN IF NOT EXISTS driver_join_policy text NOT NULL DEFAULT 'approval'
    CHECK (driver_join_policy IN ('approval','open'));

UPDATE public.organisations
SET join_policy = 'allowlist'
WHERE org_type = 'conference'
  AND join_policy = 'open';

ALTER TABLE public.org_join_requests
  ADD COLUMN IF NOT EXISTS requested_role TEXT NOT NULL DEFAULT 'user'
    CHECK (requested_role IN ('user', 'driver'));


-- ─────────────────────────────────────────────────────────────
-- 3. CHECK CONSTRAINT  (events_date_not_past)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.events
  DROP CONSTRAINT IF EXISTS events_date_not_past;
ALTER TABLE public.events
  ADD CONSTRAINT events_date_not_past
    CHECK (event_date > now() - interval '1 hour');


-- ─────────────────────────────────────────────────────────────
-- 4. INDEXES
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
CREATE INDEX IF NOT EXISTS idx_organisations_org_token
  ON public.organisations (org_token);
CREATE INDEX IF NOT EXISTS idx_org_join_requests_status
  ON public.org_join_requests (status);
CREATE INDEX IF NOT EXISTS idx_profiles_org_role
  ON public.profiles (org_id, role);
CREATE INDEX IF NOT EXISTS idx_events_org_status_date
  ON public.events (org_id, status, event_date);
CREATE INDEX IF NOT EXISTS idx_events_driver_status_date
  ON public.events (assigned_driver_id, status, event_date);
CREATE INDEX IF NOT EXISTS idx_pickups_event_order
  ON public.pickup_requests (event_id, pickup_order);
CREATE INDEX IF NOT EXISTS idx_pickups_user_event_status
  ON public.pickup_requests (user_id, event_id, status);
CREATE INDEX IF NOT EXISTS idx_org_join_requests_org_status_created
  ON public.org_join_requests (org_id, status, created_at);
CREATE INDEX IF NOT EXISTS idx_organisations_name_trgm
  ON public.organisations USING gin (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_organisations_city_trgm
  ON public.organisations USING gin (city gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_events_name_trgm
  ON public.events USING gin (name gin_trgm_ops);


-- ═══════════════════════════════════════════════════════════════
-- 5. FUNCTIONS  (CREATE OR REPLACE — always safe to re-run)
-- ═══════════════════════════════════════════════════════════════

-- ── Helper: get caller's org_id without RLS recursion ─────────
CREATE OR REPLACE FUNCTION public.get_my_org_id()
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT org_id FROM public.profiles WHERE id = auth.uid()
$$;

-- ── Helper: get caller's role without RLS recursion ───────────
CREATE OR REPLACE FUNCTION public.get_my_role()
RETURNS text LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid()
$$;

-- ── Create organisation + claim admin role (atomic) ───────────
CREATE OR REPLACE FUNCTION public.create_organisation_and_admin(
  org_name    text,
  org_city    text    DEFAULT NULL,
  org_country text    DEFAULT NULL,
  org_type    text    DEFAULT 'church',
  p_full_name text    DEFAULT ''
)
RETURNS uuid
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

  INSERT INTO public.organisations (
    name,
    city,
    country,
    org_type,
    join_policy,
    driver_join_policy
  )
  VALUES (
    trim(org_name),
    NULLIF(trim(COALESCE(org_city, '')), ''),
    NULLIF(trim(COALESCE(org_country, '')), ''),
    org_type,
    CASE WHEN org_type = 'conference' THEN 'allowlist' ELSE 'open' END,
    'approval'
  )
  RETURNING id INTO new_org_id;

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

-- ── Join with invite code (atomic) ────────────────────────────
CREATE OR REPLACE FUNCTION public.join_organisation_with_code(
  invite_code text,
  p_full_name text   DEFAULT '',
  p_phone     text   DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  inv     public.org_invites%ROWTYPE;
  granted text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;

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

  UPDATE public.org_invites
  SET    use_count  = use_count + 1,
         is_active  = (use_count + 1 < max_uses)
  WHERE  id = inv.id;

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

-- ── Generate invite code (admin only) ─────────────────────────
CREATE OR REPLACE FUNCTION public.generate_invite_code(
  p_role        text,
  p_expires_at  timestamptz DEFAULT NULL,
  p_max_uses    int         DEFAULT 1
)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  admin_org_id uuid;
  new_code     text;
BEGIN
  IF p_role NOT IN ('driver', 'user') THEN
    RAISE EXCEPTION 'Role must be ''driver'' or ''user''.';
  END IF;

  SELECT org_id INTO admin_org_id
  FROM   public.profiles
  WHERE  id = auth.uid() AND role = 'admin';

  IF admin_org_id IS NULL THEN
    RAISE EXCEPTION 'Only organisation admins can generate invite codes.';
  END IF;

  IF p_max_uses < 1 THEN
    RAISE EXCEPTION 'max_uses must be at least 1.';
  END IF;

  LOOP
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.org_invites WHERE code = new_code);
  END LOOP;

  INSERT INTO public.org_invites (org_id, code, role, created_by, expires_at, max_uses)
  VALUES (admin_org_id, new_code, p_role, auth.uid(), p_expires_at, p_max_uses);

  RETURN new_code;
END;
$$;

-- ── Join via QR/link token with org access policy ─────────────
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
  v_policy TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated.';
  END IF;

  IF p_role NOT IN ('user', 'driver') THEN
    RAISE EXCEPTION 'Invalid role. Must be user or driver.';
  END IF;

  SELECT * INTO v_org FROM public.organisations WHERE org_token = p_token;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Invalid or expired invite link. Ask your administrator to share a new one.';
  END IF;

  v_policy := CASE
    WHEN p_role = 'driver' THEN v_org.driver_join_policy
    ELSE v_org.join_policy
  END;

  IF v_policy = 'approval' THEN
    INSERT INTO public.org_join_requests (org_id, user_id, requested_role, status)
    VALUES (v_org.id, auth.uid(), p_role, 'pending')
    ON CONFLICT (org_id, user_id) DO UPDATE
      SET requested_role = EXCLUDED.requested_role,
          status = 'pending',
          created_at = now()
      WHERE public.org_join_requests.status != 'approved';

    RETURN 'pending';
  END IF;

  IF v_policy = 'allowlist' THEN
    v_email := (SELECT email FROM auth.users WHERE id = auth.uid());

    IF v_email IS NULL OR NOT EXISTS (
      SELECT 1 FROM public.org_email_allowlist
      WHERE org_id = v_org.id
        AND lower(email) = lower(v_email)
        AND claimed = false
    ) THEN
      RAISE EXCEPTION
        'Your email is not on the approved attendee list. '
        'Request access from the organiser if you believe this is a mistake.';
    END IF;

    UPDATE public.org_email_allowlist
      SET claimed = true
      WHERE org_id = v_org.id
        AND lower(email) = lower(v_email)
        AND claimed = false;
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

-- ── Reset org token (admin only) ──────────────────────────────
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

-- ── Get org details from token (public / pre-auth lookup) ─────
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

-- ── Approve join request (admin only) ─────────────────────────
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
  UPDATE public.profiles
  SET org_id = v_req.org_id,
      role = v_req.requested_role
  WHERE id = v_req.user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_join_request(BIGINT) TO authenticated;

-- ── Reject join request (admin only) ──────────────────────────
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

-- ── Update org access settings (admin only) ───────────────────
CREATE OR REPLACE FUNCTION public.update_org_access_settings(
  p_join_policy TEXT,
  p_driver_join_policy TEXT,
  p_searchable BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF get_my_role() != 'admin' OR get_my_org_id() IS NULL THEN
    RAISE EXCEPTION 'Only organisation admins can update access settings.';
  END IF;

  IF p_join_policy NOT IN ('open', 'approval', 'allowlist') THEN
    RAISE EXCEPTION 'Invalid attendee join policy.';
  END IF;

  IF p_driver_join_policy NOT IN ('approval', 'open') THEN
    RAISE EXCEPTION 'Invalid driver join policy.';
  END IF;

  UPDATE public.organisations
  SET join_policy = p_join_policy,
      driver_join_policy = p_driver_join_policy,
      searchable = COALESCE(p_searchable, searchable)
  WHERE id = get_my_org_id();
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_org_access_settings(TEXT, TEXT, BOOLEAN) TO authenticated;

-- ── Add allowlist email (admin only) ──────────────────────────
CREATE OR REPLACE FUNCTION public.add_allowlist_email(p_email TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT;
BEGIN
  IF get_my_role() != 'admin' OR get_my_org_id() IS NULL THEN
    RAISE EXCEPTION 'Only organisation admins can manage the allowlist.';
  END IF;

  v_email := lower(trim(COALESCE(p_email, '')));
  IF v_email = '' OR v_email !~* '^[^@]+@[^@]+\.[^@]+$' THEN
    RAISE EXCEPTION 'Enter a valid email address.';
  END IF;

  INSERT INTO public.org_email_allowlist (org_id, email)
  VALUES (get_my_org_id(), v_email)
  ON CONFLICT (org_id, email) DO UPDATE
    SET claimed = public.org_email_allowlist.claimed;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_allowlist_email(TEXT) TO authenticated;

-- ── Remove allowlist email (admin only) ───────────────────────
CREATE OR REPLACE FUNCTION public.remove_allowlist_email(p_id BIGINT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF get_my_role() != 'admin' OR get_my_org_id() IS NULL THEN
    RAISE EXCEPTION 'Only organisation admins can manage the allowlist.';
  END IF;

  DELETE FROM public.org_email_allowlist
  WHERE id = p_id
    AND org_id = get_my_org_id();
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_allowlist_email(BIGINT) TO authenticated;

-- ── Search organisations (server-side, injection-safe) ────────
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

GRANT EXECUTE ON FUNCTION public.search_organisations(TEXT) TO anon, authenticated;

-- ── Persist pickup route atomically (Edge Function service-role path) ─────
CREATE OR REPLACE FUNCTION public.persist_pickup_route(
  p_event_id BIGINT,
  p_ordered JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_expected INTEGER;
  v_updated  INTEGER;
BEGIN
  IF p_ordered IS NULL OR jsonb_typeof(p_ordered) != 'array' THEN
    RAISE EXCEPTION 'Ordered route payload must be a JSON array.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.events
    WHERE id = p_event_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'Event is not active or does not exist.';
  END IF;

  v_expected := jsonb_array_length(p_ordered);
  IF v_expected = 0 THEN
    RETURN p_ordered;
  END IF;

  WITH stops AS (
    SELECT *
    FROM jsonb_to_recordset(p_ordered)
      AS x(pickup_id BIGINT, "order" INTEGER, eta_minutes INTEGER)
  ),
  updated AS (
    UPDATE public.pickup_requests pr
    SET pickup_order = stops."order",
        eta_minutes  = stops.eta_minutes,
        status       = 'pending'
    FROM stops
    WHERE pr.id = stops.pickup_id
      AND pr.event_id = p_event_id
      AND pr.status = 'pending'
    RETURNING pr.id
  )
  SELECT count(*) INTO v_updated FROM updated;

  IF v_updated != v_expected THEN
    RAISE EXCEPTION
      'Route persistence failed: updated % of % pickup rows.',
      v_updated,
      v_expected;
  END IF;

  RETURN p_ordered;
END;
$$;

GRANT EXECUTE ON FUNCTION public.persist_pickup_route(BIGINT, JSONB) TO service_role;


-- ═══════════════════════════════════════════════════════════════
-- 6. TRIGGER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════

-- ── Auto-set org_id + admin_id on event insert ────────────────
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

-- ── Auto-create profile row on new auth signup ────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, role, full_name)
  VALUES (
    NEW.id,
    'user',
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
-- 7. ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════

ALTER TABLE public.organisations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_invites         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pickup_requests     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_email_allowlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.org_join_requests   ENABLE ROW LEVEL SECURITY;

-- Drop ALL existing policies on public tables before recreating
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
-- Members read their own org only.
CREATE POLICY "orgs_select_own"
  ON public.organisations FOR SELECT
  USING (id = public.get_my_org_id());

-- Searchable orgs are visible to any authenticated user (join flow)
CREATE POLICY "orgs_search_select"
  ON public.organisations FOR SELECT
  USING (searchable = true);

-- Admin can update their org
CREATE POLICY "orgs_update_admin"
  ON public.organisations FOR UPDATE
  USING (id = public.get_my_org_id() AND public.get_my_role() = 'admin');

-- ── PROFILES ──────────────────────────────────────────────────
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
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND role = public.get_my_role()
    AND org_id IS NOT DISTINCT FROM public.get_my_org_id()
  );

-- ── ORG INVITES ───────────────────────────────────────────────
CREATE POLICY "invites_select_admin"
  ON public.org_invites FOR SELECT
  USING (
    org_id = public.get_my_org_id()
    AND public.get_my_role() = 'admin'
  );

-- Admin can deactivate (update) invite codes in their org
CREATE POLICY "invites_update_admin"
  ON public.org_invites FOR UPDATE
  USING (
    org_id = public.get_my_org_id()
    AND public.get_my_role() = 'admin'
  );

-- ── EVENTS ────────────────────────────────────────────────────
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
  WITH CHECK (public.get_my_role() = 'admin');

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
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.org_id = public.get_my_org_id()
        AND e.status = 'active'
    )
  );

CREATE POLICY "subs_delete_own"
  ON public.event_subscriptions FOR DELETE
  USING (auth.uid() = user_id);

-- ── PICKUP REQUESTS ───────────────────────────────────────────
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

CREATE POLICY "pickups_select_admin"
  ON public.pickup_requests FOR SELECT
  USING (
    public.get_my_role() = 'admin'
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.org_id = public.get_my_org_id()
    )
  );

CREATE POLICY "pickups_insert_own"
  ON public.pickup_requests FOR INSERT
  WITH CHECK (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.org_id = public.get_my_org_id()
        AND e.status = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.event_subscriptions s
      WHERE s.event_id = event_id
        AND s.user_id = auth.uid()
    )
  );

CREATE POLICY "pickups_update_own"
  ON public.pickup_requests FOR UPDATE
  USING (
    auth.uid() = user_id
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.org_id = public.get_my_org_id()
    )
  )
  WITH CHECK (
    auth.uid() = user_id
    AND status = 'pending'
    AND pickup_order IS NULL
    AND eta_minutes IS NULL
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.org_id = public.get_my_org_id()
    )
  );

CREATE POLICY "pickups_update_driver"
  ON public.pickup_requests FOR UPDATE
  USING (
    public.get_my_role() = 'driver'
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.assigned_driver_id = auth.uid()
        AND e.org_id = public.get_my_org_id()
    )
  )
  WITH CHECK (
    public.get_my_role() = 'driver'
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_id
        AND e.assigned_driver_id = auth.uid()
        AND e.org_id = public.get_my_org_id()
    )
  );

-- ── ORG EMAIL ALLOWLIST ───────────────────────────────────────
CREATE POLICY "allowlist_admin"
  ON public.org_email_allowlist FOR ALL
  USING (
    public.get_my_role() = 'admin' AND org_id = public.get_my_org_id()
  )
  WITH CHECK (
    public.get_my_role() = 'admin' AND org_id = public.get_my_org_id()
  );

-- ── ORG JOIN REQUESTS ─────────────────────────────────────────
CREATE POLICY "requests_own_select"
  ON public.org_join_requests FOR SELECT
  USING (user_id = auth.uid());

CREATE POLICY "requests_own_insert"
  ON public.org_join_requests FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND requested_role IN ('user', 'driver')
  );

CREATE POLICY "requests_admin_select"
  ON public.org_join_requests FOR SELECT
  USING (
    public.get_my_role() = 'admin' AND org_id = public.get_my_org_id()
  );

CREATE POLICY "requests_admin_update"
  ON public.org_join_requests FOR UPDATE
  USING (
    public.get_my_role() = 'admin' AND org_id = public.get_my_org_id()
  );


-- ═══════════════════════════════════════════════════════════════
-- Done. All tables, columns, functions, triggers and RLS
-- policies are now in the correct state.
-- ═══════════════════════════════════════════════════════════════
