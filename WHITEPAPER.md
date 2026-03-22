# Rover — Platform Whitepaper

> **Living document.** Each section is scoped to a specific component of the system.
> When a component changes, update only its section and increment the version table below.
> The rest of the document stays valid.

---

## Version History

| Version | Date       | Changed Section(s)          | Summary                                                                                     |
|---------|------------|-----------------------------|---------------------------------------------------------------------------------------------|
| 1.0     | 2026-03-18 | All                         | Initial whitepaper — covers Phase A–C (multi-tenant, onboarding, token join, deep links)   |
| 2.0     | 2026-03-22 | All                         | Full rewrite — FCM HTTP v1, driver map, en_route status, security hardening, schema v6, in-app guide |

---

## Table of Contents

1. [Purpose & Problem Statement](#1-purpose--problem-statement)
2. [Target Organisations](#2-target-organisations)
3. [Roles & Permissions](#3-roles--permissions)
4. [System Architecture](#4-system-architecture)
5. [Database Schema](#5-database-schema)
6. [Security Model](#6-security-model)
7. [Onboarding Flow](#7-onboarding-flow)
8. [Event Management](#8-event-management)
9. [Pickup & Route Optimisation](#9-pickup--route-optimisation)
10. [Driver Map Interface](#10-driver-map-interface)
11. [Real-Time Updates](#11-real-time-updates)
12. [Deep Links & QR Codes](#12-deep-links--qr-codes)
13. [Conference Org Support](#13-conference-org-support)
14. [Notifications (FCM HTTP v1)](#14-notifications-fcm-http-v1)
15. [In-App Help System](#15-in-app-help-system)
16. [Technology Stack](#16-technology-stack)
17. [Platform Support](#17-platform-support)
18. [Security Audit & Hardening](#18-security-audit--hardening)
19. [Known Limitations & Roadmap](#19-known-limitations--roadmap)

---

## 1. Purpose & Problem Statement

Rover is a mobile platform that solves a coordination problem common to churches, conferences, schools, and other community organisations: **getting people to events when they don't have their own transport**.

Without Rover, an organiser must manually collect addresses, phone drivers individually, and figure out pickup order by hand. Drivers receive information piecemeal, often by WhatsApp message. Attendees don't know when the driver is coming. The entire process is slow, error-prone, and doesn't scale past a handful of attendees.

Rover replaces this with a structured, real-time flow:

- Attendees register their GPS pickup location through the app in seconds.
- The system computes an optimised pickup route automatically.
- Drivers follow a sorted, live-updated pickup list and map with ETAs.
- Attendees see exactly when their driver will arrive.

The platform is **multi-tenant**: each organisation is an isolated workspace. One Rover installation serves any number of churches, conferences, or schools simultaneously, with no data leakage between them.

---

## 2. Target Organisations

Rover is designed for any organisation that runs recurring or one-off events requiring coordinated transport. The current `org_type` taxonomy covers:

| Type          | Description                                                             |
|---------------|-------------------------------------------------------------------------|
| `church`      | Weekly or special services, youth groups, retreats                      |
| `conference`  | One-time or annual events with a fixed attendee list (email-gated)      |
| `corporate`   | Company offsites, team events, airport transfers                        |
| `school`      | Field trips, sports events, parent-run carpools                         |
| `other`       | Any organisation not covered by the above                               |

Conference-type organisations have additional access controls: only people whose email addresses appear on a pre-uploaded allowlist can join, and each slot can only be claimed once.

---

## 3. Roles & Permissions

Every user in Rover belongs to exactly one organisation and holds exactly one role within it.

| Role     | Can Do                                                                                                                          |
|----------|---------------------------------------------------------------------------------------------------------------------------------|
| `admin`  | Create and manage the organisation; create/edit/cancel events; assign drivers; manage members; approve/reject join requests; reset invite token |
| `driver` | View events assigned to them; start route optimisation; mark pickups as en route or completed; view live map with GPS tracking  |
| `user`   | Browse and search events in their org; subscribe to events; request a pickup with GPS location; view live driver ETA            |

Roles are set server-side via SECURITY DEFINER RPCs. A client cannot self-promote to admin or driver by modifying a request.

---

## 4. System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                       │
│  Android + iOS                                              │
│  ┌──────────────┐  ┌─────────────┐  ┌───────────────────┐  │
│  │   Screens    │  │  Services   │  │  Supabase client  │  │
│  │  LoginPage   │  │ AuthService │  │  (PostgREST +     │  │
│  │  AdminHome   │  │ OrgService  │  │   Realtime WS)    │  │
│  │  DriverHome  │  │ EventService│  └───────────────────┘  │
│  │  DriverMap   │  │PickupService│                          │
│  │  UserHome    │  └─────────────┘                          │
│  │  EventDetail │                                           │
│  │  UserGuide   │                                           │
│  └──────────────┘                                           │
└──────────────────────────┬──────────────────────────────────┘
                           │ HTTPS / WebSocket
┌──────────────────────────▼──────────────────────────────────┐
│                       Supabase                              │
│  ┌────────────────┐  ┌──────────┐  ┌────────────────────┐  │
│  │  PostgreSQL    │  │  Auth    │  │     Realtime       │  │
│  │  + PostGIS     │  │  (JWT)   │  │  (WebSocket /      │  │
│  │  RLS on all    │  │  Email/  │  │   logical repl.)   │  │
│  │  tables        │  │  Password│  └────────────────────┘  │
│  └────────────────┘  └──────────┘                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Edge Functions (Deno)                               │   │
│  │   schedule-pickup  — route optimisation + FCM notify │   │
│  │   send-notification — FCM HTTP v1 push delivery      │   │
│  └──────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │  OAuth 2.0 JWT
┌──────────────────────────▼──────────────────────────────────┐
│            Firebase Cloud Messaging (FCM HTTP v1)           │
│  Push notifications to driver and attendee devices          │
│  Service account credentials stored as Supabase secret      │
└─────────────────────────────────────────────────────────────┘
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| All privileged logic in SECURITY DEFINER RPCs | Client is treated as untrusted. DB validates all mutations server-side. |
| Route optimisation in an Edge Function | Needs service-role credentials to bypass RLS. Keeps business logic off the client. |
| Supabase Realtime (no polling) | PostgreSQL logical replication → WebSocket. ~100ms propagation. Zero client polling. |
| FCM used only for push notifications | App state is always sourced from Supabase. FCM is one-way delivery, not state. |
| OpenStreetMap tiles (no API key) | Driver map uses `flutter_map` + OSM tiles. No billing, no quota, no key management. |
| Cross-referenced profiles cache | Supabase `.stream()` cannot join tables. Profiles pre-fetched and passed as a map to the realtime stream. |

---

## 5. Database Schema

All tables live in the `public` schema of a single Supabase PostgreSQL instance. The PostGIS extension provides geographic data types and spatial queries.

### 5.1 Core Tables

#### `organisations`
The tenant boundary. Every piece of data is scoped to one organisation.

| Column       | Type          | Notes                                                         |
|--------------|---------------|---------------------------------------------------------------|
| `id`         | uuid PK       | `gen_random_uuid()`                                           |
| `name`       | text          | Display name                                                  |
| `city`       | text          | Optional                                                      |
| `country`    | text          | Optional                                                      |
| `org_type`   | text          | `church` / `conference` / `corporate` / `school` / `other`   |
| `org_token`  | uuid UNIQUE   | Single-use invite token; powers QR code and share link        |
| `searchable` | boolean       | `true` = discoverable in search; `false` = hidden (conference default) |
| `created_at` | timestamptz   |                                                               |

**Index:** `idx_organisations_org_token ON organisations(org_token)` — added in schema v6.

#### `profiles`
One row per authenticated user. `org_id` is NULL until the user completes org setup.

| Column       | Type              | Notes                                                    |
|--------------|-------------------|----------------------------------------------------------|
| `id`         | uuid PK           | FK → `auth.users(id)`                                    |
| `role`       | text              | `user` / `driver` / `admin`                              |
| `full_name`  | text              |                                                          |
| `phone`      | text              | Optional                                                 |
| `org_id`     | uuid              | FK → `organisations(id)`; NULL = no org yet              |
| `location`   | geography(POINT)  | Driver's last-known position (SRID 4326)                 |
| `fcm_token`  | text              | Firebase device token for push notifications             |
| `created_at` | timestamptz       |                                                          |

#### `events`
Created by admins. `org_id` and `admin_id` are auto-set by a BEFORE INSERT trigger.

| Column                | Type              | Notes                                          |
|-----------------------|-------------------|------------------------------------------------|
| `id`                  | bigserial PK      |                                                |
| `org_id`              | uuid              | FK → `organisations(id)` (set by trigger)      |
| `name`                | text              |                                                |
| `description`         | text              | Optional                                       |
| `location`            | geography(POINT)  | Event venue (SRID 4326)                        |
| `location_name`       | text              | Human-readable venue label                     |
| `event_date`          | timestamptz       | CHECK: must be ≥ now() + 1 hour at insert      |
| `event_type`          | text              | Free-form label (e.g. "Sunday Service")        |
| `admin_id`            | uuid              | FK → `profiles(id)` (set by trigger)           |
| `assigned_driver_id`  | uuid              | FK → `profiles(id)` (set by admin)             |
| `status`              | text              | `active` / `cancelled` / `completed`           |
| `created_at`          | timestamptz       |                                                |

#### `event_subscriptions`
Users register interest in events. Required before a pickup request can be made.

| Column       | Type         | Notes                              |
|--------------|--------------|------------------------------------|
| `id`         | bigserial PK |                                    |
| `event_id`   | bigint       | FK → `events(id)`                  |
| `user_id`    | uuid         | FK → `profiles(id)`                |
| `created_at` | timestamptz  |                                    |
| *(unique)*   |              | `(event_id, user_id)`              |

#### `pickup_requests`
A user's request for transport to a specific event.

| Column            | Type              | Notes                                                                |
|-------------------|-------------------|----------------------------------------------------------------------|
| `id`              | bigserial PK      |                                                                      |
| `event_id`        | bigint            | FK → `events(id)`                                                    |
| `user_id`         | uuid              | FK → `profiles(id)`                                                  |
| `pickup_location` | geography(POINT)  | User's GPS location (SRID 4326) — stored as WKT `POINT(lon lat)`    |
| `pickup_order`    | int               | Set by route algorithm; 1 = first stop                               |
| `eta_minutes`     | int               | Minutes from route start to this pickup                              |
| `status`          | text              | `pending` / `en_route` / `completed`                                 |
| `created_at`      | timestamptz       |                                                                      |
| *(unique)*        |                   | `(event_id, user_id)` — added in schema v6; prevents TOCTOU doubles |

### 5.2 Org Membership Tables

#### `org_invites`
Legacy invite-code table. Kept for backward compatibility. The primary join mechanism is now `org_token` (QR/link).

#### `org_email_allowlist`
Conference orgs only. Each row is a permitted attendee email.

| Column       | Type         | Notes                                              |
|--------------|--------------|----------------------------------------------------|
| `id`         | bigserial PK |                                                    |
| `org_id`     | uuid         | FK → `organisations(id)`                           |
| `email`      | text         |                                                    |
| `claimed`    | boolean      | Set to `true` when the email is used to join       |
| `created_at` | timestamptz  |                                                    |
| *(unique)*   |              | `(org_id, email)`                                  |

#### `org_join_requests`
Search-fallback join flow. Users who can't find a QR/link request access; admin approves.

| Column       | Type         | Notes                                              |
|--------------|--------------|----------------------------------------------------|
| `id`         | bigserial PK |                                                    |
| `org_id`     | uuid         | FK → `organisations(id)`                           |
| `user_id`    | uuid         | FK → `auth.users(id)`                              |
| `status`     | text         | `pending` / `approved` / `rejected`                |
| `created_at` | timestamptz  |                                                    |
| *(unique)*   |              | `(org_id, user_id)`                                |

**Index:** `idx_org_join_requests_status ON org_join_requests(status)` — added in schema v6.

### 5.3 Key RPCs (SECURITY DEFINER Functions)

| Function                          | Called By        | Purpose                                                             |
|-----------------------------------|------------------|---------------------------------------------------------------------|
| `create_organisation_and_admin()` | OrgSetupPage     | Creates org + claims admin role atomically                          |
| `join_organisation(token, role)`  | OrgSetupPage     | Validates token, sets org_id + role; checks conference allowlist    |
| `reset_org_token(org_id)`         | Admin Share tab  | Generates a new UUID token; invalidates all existing QR/links       |
| `get_org_from_token(token)`       | WelcomePage      | Public lookup (granted to `anon`) — resolves org name pre-auth      |
| `approve_join_request(id)`        | Admin Share tab  | Sets org_id on the user's profile server-side                       |
| `reject_join_request(id)`         | Admin Share tab  | Marks request as rejected                                           |
| `search_orgs(query)`              | OrgSetupPage     | Searches `searchable = true` orgs by name/city                      |
| `get_my_org_id()`                 | RLS policies     | Helper — reads caller's org without recursion                       |
| `get_my_role()`                   | RLS policies     | Helper — reads caller's role without recursion                      |

### 5.4 Database Triggers

| Trigger                | Table        | When          | Effect                                                             |
|------------------------|--------------|---------------|--------------------------------------------------------------------|
| `before_event_insert`  | `events`     | BEFORE INSERT | Auto-sets `org_id` (from caller's profile) and `admin_id` (auth.uid()) |
| `on_auth_user_created` | `auth.users` | AFTER INSERT  | Creates minimal profile row (`role='user'`, `org_id=NULL`)         |

### 5.5 RLS Policies on `pickup_requests` (schema v6)

| Policy                  | Role      | Operation | Condition                                                        |
|-------------------------|-----------|-----------|------------------------------------------------------------------|
| `pickups_select_self`   | user      | SELECT    | `user_id = auth.uid()`                                           |
| `pickups_insert_self`   | user      | INSERT    | `user_id = auth.uid()`; subscription check via event_id         |
| `pickups_select_driver` | driver    | SELECT    | Event's `assigned_driver_id = auth.uid()` AND same org           |
| `pickups_update_driver` | driver    | UPDATE    | Event's `assigned_driver_id = auth.uid()` AND same org           |
| `pickups_select_admin`  | admin     | SELECT    | Event's `org_id = get_my_org_id()`                               |

---

## 6. Security Model

Rover's security is enforced at the database layer, not the application layer. The client app is treated as untrusted.

### 6.1 Row Level Security (RLS)

RLS is enabled on every table. Policies ensure:

- **Tenant isolation**: users can only read/write data that belongs to their own organisation.
- **Role enforcement**: only admins can insert events, manage members, and approve join requests. Only assigned drivers can update pickup status.
- **Self-only writes**: users can only modify their own profile, subscriptions, and pickup requests.

RLS policies use two SECURITY DEFINER helper functions — `get_my_org_id()` and `get_my_role()` — to read the caller's profile. These helpers prevent infinite recursion that would occur if policies queried the `profiles` table directly.

### 6.2 SECURITY DEFINER RPCs

All privileged mutations — org creation, token joins, request approvals, role assignment — run as SECURITY DEFINER functions owned by the `postgres` role. This means:

- The database validates the operation server-side regardless of what the client sends.
- A client cannot call `UPDATE profiles SET role = 'admin'` directly; RLS blocks it.
- A client cannot create an org and declare themselves admin in two separate calls; the RPC does both atomically.

### 6.3 Edge Function Caller Verification

The `schedule-pickup` Edge Function previously accepted any authenticated request. As of v2.0, it:

1. Builds a user-scoped Supabase client from the caller's JWT.
2. Fetches the event using that client — RLS ensures the caller is in the same org.
3. Compares `event.assigned_driver_id` to the caller's `auth.uid()`.
4. Returns HTTP 403 if the caller is not the assigned driver.
5. Only then switches to a service-role client for the privileged writes.

This prevents any authenticated user from corrupting route data for any event.

### 6.4 Invite Token Security

The invite token (`org_token`) is a UUID (128 bits of entropy). A brute-force attack against the join endpoint would require ≈ 2¹²⁸ guesses. Tokens can be rotated instantly by the admin, invalidating all previously shared QR codes and links.

The `join_organisation` RPC validates the UUID format server-side. The client performs a pre-validation regex check to surface clear error messages before the network call.

### 6.5 TOCTOU Race Condition Protection

`pickup_requests` carries a `UNIQUE (event_id, user_id)` constraint (added in schema v6). If a user double-taps "Request Pickup" and two concurrent inserts arrive, the database guarantees only one row is written. The client-side duplicate check is a UX guard; the constraint is the authoritative guarantee.

### 6.6 Conference Gating

For `org_type = 'conference'`, the `join_organisation()` RPC additionally:

1. Checks that the caller's verified email is on the `org_email_allowlist`.
2. Marks the email slot as `claimed = true` so the same email cannot be used twice.
3. Returns an error if the email is not on the list.

This ensures that only registered attendees can access a conference org.

---

## 7. Onboarding Flow

The onboarding design follows a single rule: **the user never sees the word "role"**. Cards use plain language. The system infers role from the user's selection.

```
App Launch
    │
    ├─ Has session ──► _checkSession()
    │                      ├─ no_org  ──► OrgSetupPage
    │                      ├─ admin   ──► AdminHomePage
    │                      ├─ driver  ──► DriverHomePage
    │                      └─ user    ──► UserHomePage
    │
    └─ No session ──► LoginPage
                          │
                          ├─ Sign In ──► (as above)
                          │
                          └─ CREATE AN ACCOUNT ──► WelcomePage
                                                        │
                              ┌─────────────────────────┤──────────────────────────┐
                              │                         │                          │
                    "I'm organising"            "I'm a driver"            "I'm attending"
                              │                         │                          │
                         RegisterPage             RegisterPage              RegisterPage
                         (role=admin)            (role=driver)             (role=user)
                              │                         │                          │
                         OrgSetupPage             OrgSetupPage              OrgSetupPage
                         (Tab A: Create)          (Tab B: Join)             (Tab B: Join)
                              │                         │                          │
                        AdminHomePage           DriverHomePage             UserHomePage
```

### 7.1 Cold-Start Race Fix

`_initDeepLinks()` is now awaited before `_checkSession()` (fix M-1). Previously these ran concurrently — a fast session check could route the user before the deep-link token was stored, dropping the invite.

### 7.2 Token Persistence

`PendingLink.orgToken` is persisted to `SharedPreferences` (fix M-2). If the user registers, is asked to confirm their email, and the app is killed during that wait, the token survives and is loaded back on next launch.

### 7.3 Deep Link Onboarding

When a user taps a `rover.app/join/TOKEN` link before having an account:

1. The OS hands the URI to the app via `app_links`.
2. `PendingLink.setToken()` writes the token to memory and `SharedPreferences`.
3. `WelcomePage` resolves the org name via `get_org_from_token()` (granted to `anon`) and shows a banner: *"Joining: [Org Name]"*.
4. The user selects their role, registers, and is taken to `OrgSetupPage` with the token pre-filled.
5. Tapping "Join Organisation" calls `join_organisation(token, role)` and routes to their home screen.
6. `PendingLink.clear()` removes the token from memory and disk.

**Target: ≤ 5 taps from cold link to home screen.**

### 7.4 FCM Token Registration Timing

`AuthService.registerFcmToken()` is called on login AND immediately after a successful org join (fix M-7). Previously it was only called on login, meaning users who registered and joined without email confirmation (i.e. session immediately active) never had their FCM token saved to the database.

---

## 8. Event Management

### 8.1 Admin

Admins manage events from the Events tab of `AdminHomePage`:

- **Create**: name (required), date/time (minimum 1 hour in the future, enforced by DB CHECK constraint), description, venue name, type. The BEFORE INSERT trigger auto-assigns `org_id` and `admin_id`.
- **Edit**: update name, description, type, venue name, date/time.
- **Cancel**: soft-delete via `status = 'cancelled'`. Cancelled events remain in the database but are hidden from non-admin users.
- **Assign driver**: dropdown of all `driver`-role users in the org. Sets `assigned_driver_id` on the event.
- **View attendees**: list of subscribed users with name and phone number.

### 8.2 Members Tab

The Members tab shows all `driver` and `user` role members in the organisation, with their name, role badge, and join date.

### 8.3 Share Tab

The Share tab provides three mechanisms for growing the organisation:

| Mechanism        | How                                                           |
|------------------|---------------------------------------------------------------|
| QR code          | Displayed via `qr_flutter`; encodes the `rover.app/join/TOKEN` URL |
| Share link       | Native OS share sheet via `share_plus`; shares the full URL  |
| Reset code       | Generates a new `org_token`; all previous links and QR codes immediately invalid |
| Pending requests | Displays users who searched and requested access; admin taps Approve or Reject |

### 8.4 Users (Attendees)

From `UserHomePage`, users browse and search events by name or type. Tapping an event opens `EventDetailPage` where they can:

- **Subscribe / Unsubscribe** — toggle attendance registration.
- **Request Pickup** — only available after subscribing. Submits the user's current GPS location. Once submitted, the button is permanently replaced with a green "Pickup Requested" indicator (fix L-6).
- **View ETA** — once the driver starts the route, a live ETA card appears showing pickup order, countdown, and status.

---

## 9. Pickup & Route Optimisation

### 9.1 Pickup Request

When a user taps "Request Pickup":

1. The app calls `Geolocator.getCurrentPosition()` in high-accuracy mode.
2. Coordinates are validated (latitude: −90 to 90; longitude: −180 to 180).
3. A pre-check queries for existing pickup requests for this user and event — client-side guard against doubles.
4. A row is inserted into `pickup_requests` with `pickup_location = 'POINT(lon lat)'` and `status = 'pending'`.
5. The DB UNIQUE constraint on `(event_id, user_id)` enforces deduplication at the server level regardless of race conditions.

### 9.2 Route Computation

When the assigned driver taps "Start Route":

1. The app reads the driver's current GPS position via `Geolocator`.
2. A POST request is sent to the `schedule-pickup` Supabase Edge Function with `{event_id, driver_lat, driver_lon}` and the caller's JWT.
3. The function:
   - **Verifies** the caller is the assigned driver (see §6.3).
   - **Fetches** all `pending` pickup requests for the event using service-role credentials.
   - **Runs** the greedy nearest-neighbour algorithm from the driver's position.
   - **Writes** `pickup_order` and `eta_minutes` back to each `pickup_requests` row.
   - **Sends** an FCM push notification to the first user via `send-notification`.
   - **Returns** the ordered list to the app.
4. The driver sees a sorted pickup list in `DriverHomePage`.
5. A "View Map" FAB appears, opening `DriverMapPage`.

### 9.3 Pickup Status Lifecycle

Each pickup row progresses through three states:

```
pending ──► en_route ──► completed
```

| State       | Trigger                              | Visible To                              |
|-------------|--------------------------------------|-----------------------------------------|
| `pending`   | Route computed (or request created)  | Driver sees "Waiting"; user sees status |
| `en_route`  | Driver taps "On My Way" (car icon)   | Driver sees blue; user sees "En Route"  |
| `completed` | Driver taps "Done" (tick icon)       | Driver sees green; user sees "Picked Up"|

The "On My Way" button appears only when status is `pending`. The "Done" button is always visible for non-completed pickups. Both actions are available from the pickup list in `DriverHomePage` and from the map bottom sheet in `DriverMapPage`.

### 9.4 Algorithm

The current implementation uses a **greedy nearest-neighbour** algorithm (O(n²)):

```
INPUT: driver position (lat, lon), list of n pickup stops

1. Set current = driver position, cumulative_km = 0
2. While stops remain:
   a. Find the nearest unvisited stop to current (Haversine distance)
   b. cumulative_km += distance to that stop
   c. eta_minutes = round((cumulative_km / 30 km/h) × 60)
   d. Assign pickup_order and eta_minutes
   e. current = that stop
   f. Remove from remaining list
3. Return ordered list
```

Adequate for typical fleet sizes (< 50 pickups per event). For larger events, a 2-opt or OR-Tools optimiser would improve route quality.

### 9.5 Re-routing

If the driver taps "Re-route" on an active event, the full `schedule-pickup` flow repeats from the driver's current position. Only `pending` pickups (not `completed` ones) are passed to the algorithm, so completed stops are never revisited.

---

## 10. Driver Map Interface

`DriverMapPage` provides a full-screen map view during a live pickup route.

### 10.1 Map Layer

- **Tiles**: OpenStreetMap via `flutter_map`. No API key or billing account required.
- **Driver marker**: white circle with green border and car icon, updated every 10 metres via `Geolocator.getPositionStream()`.
- **Pickup markers**: numbered circles coloured by status — blue (pending/default), light blue (en_route), grey with a tick (completed).
- **Summary banner**: persistent top bar showing "N stops remaining of M".

### 10.2 Camera Controls

| Action               | Icon       | Behaviour                                               |
|----------------------|------------|---------------------------------------------------------|
| Centre on driver     | my_location| Moves camera to driver's current GPS position at zoom 15|
| Fit all stops        | fit_screen | Computes `LatLngBounds` of all markers; pads by 60 dp   |
| Tap a list row       | (tap)      | Centres map on that pickup's GPS pin at zoom 16         |

On first data arrival, the map auto-fits all markers via `_fitBounds()` called inside `addPostFrameCallback`.

### 10.3 Bottom Sheet List

Below the map (flex ratio 3:2), a `ListView` shows all pickups in order:

- Struck-through, greyed names for completed pickups.
- ETA and phone number on the subtitle row.
- Status label chip (Waiting / En Route / Picked Up).
- Car icon button (→ `en_route`) and tick button (→ `completed`) for non-completed pickups.

Tapping any row centres the map on that pin.

### 10.4 Location Data

The map receives the `profilesCache` map from `DriverHomePage` (a `userId → {full_name, phone}` lookup). This is necessary because Supabase `.stream()` cannot perform PostgREST JOIN queries — profile data must be cross-referenced client-side.

---

## 11. Real-Time Updates

Rover uses Supabase Realtime (PostgreSQL logical replication → WebSocket) for two live streams:

| Stream                         | Subscriber      | Triggers When                                             |
|--------------------------------|-----------------|-----------------------------------------------------------|
| `listenToPickupUpdates(event)` | Driver screens  | Any `pickup_requests` row for the event changes           |
| `listenToMyPickup(event)`      | User screen     | The current user's own `pickup_requests` row changes      |

Both streams are opened as typed `Stream<...>` via `PickupService` and consumed by `StreamBuilder` widgets. No polling occurs anywhere in the app.

### 11.1 ETA Card States (User View)

The ETA card in `EventDetailPage` handles four distinct states:

| State                        | Display                                           |
|------------------------------|---------------------------------------------------|
| Stream connecting            | 4 dp linear progress bar (non-blocking)           |
| Stream error                 | Orange warning card with reconnect message        |
| No pickup request            | Nothing (card hidden)                             |
| Pickup exists, no driver yet | Blue info card: "Waiting for a driver to be assigned" |
| Route started                | Blue ETA card: stop number, ETA minutes, status  |

---

## 12. Deep Links & QR Codes

Every organisation has a single `org_token` (UUID). This token is used in two ways:

- **QR code** — rendered in the admin Share tab via `qr_flutter`. Scanning opens `rover.app/join/TOKEN` directly in the app.
- **Share link** — `https://rover.app/join/TOKEN`. Shared via the native share sheet (`share_plus`) or copied to clipboard.

Both encode the same token. The admin can reset the token at any time, invalidating all outstanding QR codes and links.

### 12.1 Platform Deep Link Config

| Platform | Mechanism                                          | Status                                                             |
|----------|----------------------------------------------------|---------------------------------------------------------------------|
| Android  | `intent-filter` with `android:autoVerify=true`    | Configured in `AndroidManifest.xml`                                |
| iOS      | `applinks:rover.app` in `Runner.entitlements`      | File created; must be wired in Xcode Build Settings before release |

### 12.2 Token Parsing

The client accepts both a full URL (`https://rover.app/join/UUID`) and a bare UUID. Parsing logic:

1. Try `Uri.parse()` on the input.
2. If the URI has path segments and one is `join`, extract the segment that follows.
3. Otherwise treat the raw input as a bare token.
4. Validate the resolved token against a UUID regex before calling the RPC.

If validation fails, the user sees: *"That doesn't look like a Rover invite code. Ask your administrator to share the link again."*

### 12.3 Join Methods (priority order)

1. **QR scan** — camera icon in OrgSetupPage Tab B; `MobileScanner` reads the code, validates, and auto-joins.
2. **Link paste / deep link** — text field accepts full URL or bare UUID; deep link handler pre-fills the field.
3. **Search fallback** — small text link at bottom of Tab B opens a search dialog; user requests access; admin approves from Share tab.

---

## 13. Conference Org Support

Conference-type organisations differ from community orgs in three ways:

| Feature                  | Community org (`church`, etc.)     | Conference org                                |
|--------------------------|------------------------------------|-----------------------------------------------|
| Discoverable in search   | Yes (`searchable = true`)          | No (`searchable = false`)                     |
| Who can join             | Anyone with the token              | Only emails on the `org_email_allowlist`      |
| Email slot reuse         | N/A                                | Each email can only be claimed once (`claimed = true`) |

**Admin workflow:**

1. Create org with `org_type = 'conference'`. The `searchable` flag defaults to `false`.
2. Upload attendee emails to `org_email_allowlist` (via Supabase SQL Editor or a future admin UI).
3. Share the QR code / link as normal.
4. Attendees who tap the link have their email checked against the allowlist; their slot is marked `claimed`.

---

## 14. Notifications (FCM HTTP v1)

### 14.1 Overview

Firebase Cloud Messaging is integrated for push notifications. The FCM Legacy HTTP API was shut down by Google in June 2024. Rover uses the **FCM HTTP v1 API** with OAuth 2.0 service account credentials.

### 14.2 Architecture

```
schedule-pickup Edge Function
         │
         └─► supabase.functions.invoke('send-notification', { user_fcm_token, title, body })
                      │
                      ▼
         send-notification Edge Function
                      │
                      ├─ Read GOOGLE_SERVICE_ACCOUNT_JSON (Supabase secret)
                      ├─ Build RS256 JWT (iss, scope, aud, iat, exp)
                      ├─ Exchange JWT for OAuth2 access token
                      │   POST https://oauth2.googleapis.com/token
                      │
                      └─ POST https://fcm.googleapis.com/v1/projects/rover-c41e5/messages:send
                             Authorization: Bearer <access_token>
                             { message: { token, notification, android, apns } }
```

### 14.3 Service Account Setup

The Firebase service account private key JSON is stored as a Supabase secret:

```powershell
# PowerShell (Windows)
$json = Get-Content "path\to\service-account.json" -Raw
supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON=$json
```

The `send-notification` function reads `GOOGLE_SERVICE_ACCOUNT_JSON`, parses the JSON, and uses `client_email`, `private_key`, and `project_id` fields to construct the JWT and the FCM endpoint URL.

### 14.4 FCM Token Lifecycle

| Event                    | Action                                                           |
|--------------------------|------------------------------------------------------------------|
| User logs in             | `AuthService.registerFcmToken()` writes token to `profiles.fcm_token` |
| User joins org (no email confirmation) | `AuthService.registerFcmToken()` called immediately after join |
| FCM token refreshed by OS | App must re-register on next login (future: `onTokenRefresh` listener) |

### 14.5 Current Notification Triggers

| Trigger              | Recipient  | Message                                        |
|----------------------|------------|------------------------------------------------|
| Driver starts route  | First user | "Your driver is on the way — You are stop #1. ETA: N minutes." |

### 14.6 Planned Notification Triggers

| Trigger                   | Recipient      | Message                          |
|---------------------------|----------------|----------------------------------|
| Driver marks pickup done  | Next user      | "You're next — driver is close"  |
| New event created         | All org users  | "New event: [name] on [date]"    |
| Join request approved     | User           | "You've been added to [org]"     |

---

## 15. In-App Help System

Every major screen carries a help icon (?) in the AppBar or header that opens `UserGuidePage`. The guide is:

- **Role-aware**: the relevant section (Organiser, Driver, Attendee) is expanded by default based on the caller's role.
- **Searchable**: a search bar filters sections and Q&A items in real time.
- **Organised by section**: Getting Started, For Organisers, For Drivers, For Attendees, Joining an Organisation, Account & Sign In, Notifications, Troubleshooting.
- **Expandable Q&A**: each section is an `ExpansionTile`; each item is a nested `ExpansionTile` with a highlighted answer card.

### 15.1 Help Entry Points

| Screen           | Entry point      | Role passed to guide |
|------------------|------------------|----------------------|
| LoginPage        | ? icon (top-right, floating over gradient) | none (shows all) |
| OrgSetupPage     | ? icon in header row | none (shows all) |
| AdminHomePage    | ? icon in AppBar | `admin` |
| DriverHomePage   | ? icon in AppBar | `driver` |
| UserHomePage     | ? icon in AppBar | `user` |
| EventDetailPage  | ? icon in AppBar | `user` |

---

## 16. Technology Stack

| Layer               | Technology                              | Version / Notes                                      |
|---------------------|-----------------------------------------|------------------------------------------------------|
| Mobile app          | Flutter (Dart)                          | 3.41.4; targets Android and iOS                      |
| Backend / DB        | Supabase (PostgreSQL 15 + PostGIS)      | Multi-tenant via RLS                                 |
| Auth                | Supabase Auth                           | Email/password; JWT; email confirmation               |
| Real-time           | Supabase Realtime                       | WebSocket; PostgreSQL logical replication             |
| Edge functions      | Supabase Edge Functions (Deno)          | `schedule-pickup`, `send-notification`               |
| Push notifications  | Firebase Cloud Messaging (HTTP v1)      | OAuth 2.0 JWT; Android + iOS                         |
| Maps                | `flutter_map` ^7.0.2                    | OpenStreetMap tiles; no API key required              |
| GPS                 | `geolocator`                            | High-accuracy mode; distance filter 10 m             |
| Deep links          | `app_links` ^6.4.1                      | Cold-start + warm link handling; SharedPreferences persistence |
| QR display          | `qr_flutter` ^4.1.0                     | Admin Share tab                                      |
| QR scan             | `mobile_scanner` ^6.0.11               | In-app camera scan on join screen                    |
| Native share        | `share_plus` ^10.1.4                    | OS share sheet for invite link                       |
| Geo storage         | PostGIS `geography(POINT, 4326)`        | Pickup locations, event venues, driver position      |
| Local storage       | `shared_preferences`                    | Deep-link token persistence                          |
| Build (Android)     | Gradle 8.11.1, AGP 8.9.1, Kotlin 2.1.0 | Upgraded in v2.0 to satisfy AndroidX camera deps    |

---

## 17. Platform Support

| Platform | Status        | Notes                                                                                           |
|----------|---------------|-------------------------------------------------------------------------------------------------|
| Android  | Supported     | Deep links configured. FCM and map working. `minSdkVersion 21`.                                |
| iOS      | Supported*    | Camera and location permissions set. Entitlements file created; Xcode wiring required before App Store release. FCM requires `GoogleService-Info.plist` placed by `flutterfire configure` on Mac. |
| Web      | Not targeted  | No web-specific UI; Supabase access would work but no responsive layout                         |
| Windows  | Dev only      | Used for development; plugin stubs generated but not shipped                                    |

\* iOS requires final platform config on a Mac before App Store submission. See pre-production checklist in §18.4.

---

## 18. Security Audit & Hardening

A full security audit was conducted against this whitepaper in March 2026. The following issues were identified and resolved:

### 18.1 High Priority (all resolved)

| ID  | Issue                                                  | Fix                                                                                |
|-----|--------------------------------------------------------|------------------------------------------------------------------------------------|
| H-1 | FCM Legacy API shut down (June 2024)                   | Migrated to FCM HTTP v1 with OAuth 2.0 service account JWT (§14)                  |
| H-2 | `schedule-pickup` accepted any authenticated caller    | Added caller identity verification; 403 if caller ≠ assigned driver (§6.3)        |
| H-3 | TOCTOU race on pickup_requests (no uniqueness)         | Added `UNIQUE (event_id, user_id)` constraint in schema v6 (§5.1)                 |

### 18.2 Medium Priority (all resolved)

| ID   | Issue                                              | Fix                                                                         |
|------|----------------------------------------------------|-----------------------------------------------------------------------------|
| M-1  | Cold-start deep link race condition                | `_initDeepLinks()` awaited before `_checkSession()` (§7.1)                  |
| M-2  | Deep-link token lost on app kill                   | Token persisted to `SharedPreferences` (§7.2)                               |
| M-3  | Driver stream missing passenger names/phones       | Profiles pre-fetched, cross-referenced by userId (§10.4)                    |
| M-4  | `_pickupOrder` not cleared on event switch         | Reset when `_activeEventId` changes (§9.2)                                  |
| M-5  | `cancelPickup` could delete completed records      | Filter added: `status != 'completed'` before delete                         |
| M-6  | FCM token not registered after org join            | `registerFcmToken()` called after successful join (§7.4)                    |
| M-7  | No index on `organisations.org_token`              | `idx_organisations_org_token` created in schema v6 (§5.1)                  |
| M-8  | Date picker allowed past dates                     | `firstDate` aligned with DB's 1-hour minimum constraint                     |
| M-9  | Admin pickup streams not including profiles        | Resolved via same profiles-cache pattern as driver stream                    |
| M-10 | `fcm_token` exposed in `getPickupRequests` select  | Column removed from select query                                            |
| M-11 | `ForgotPasswordPage` used `Uri.base.origin`        | Replaced with mobile-appropriate redirect scheme                            |
| M-12 | No index on `org_join_requests.status`             | `idx_org_join_requests_status` created in schema v6 (§5.2)                 |

### 18.3 Low Priority (resolved)

| ID  | Issue                                              | Fix                                                    |
|-----|----------------------------------------------------|--------------------------------------------------------|
| L-2 | No `en_route` status button for driver             | "On My Way" button added to list and map views (§9.3) |
| L-4 | Social login buttons were permanent no-ops         | Removed from LoginPage                                |
| L-5 | "Remember me" checkbox was a no-op                 | Removed from LoginPage                                |
| L-6 | "Request Pickup" stayed enabled after success      | Replaced with persistent "Pickup Requested" indicator (§8.4) |
| L-8 | Admin could not SELECT pickup_requests             | `pickups_select_admin` policy created in schema v6 (§5.5) |
| L-9 | Driver UPDATE policy missing on pickup_requests    | `pickups_update_driver` policy created in schema v6 (§5.5) |

### 18.4 Pre-Production Checklist

The following items are deferred pending domain registration and Mac access:

| Item                                | Blocker              | Action Required                                     |
|-------------------------------------|----------------------|-----------------------------------------------------|
| `applicationId com.example.roverfront` | Domain not yet registered | Change to reverse domain (e.g. `com.jehmni.rover`) |
| iOS `NSCameraUsageDescription`      | Requires Mac + Xcode | Add to `ios/Runner/Info.plist`                      |
| iOS `NSLocationWhenInUseUsageDescription` | Requires Mac + Xcode | Add to `ios/Runner/Info.plist`                 |
| iOS `applinks:rover.app` entitlement| Requires Mac + Xcode | Wire entitlements file in Xcode Build Settings      |
| iOS `GoogleService-Info.plist`      | Requires Mac         | Run `flutterfire configure` on Mac; copy file        |
| Release signing config              | Requires keystore    | Generate keystore; add to `build.gradle` signing config |
| App Store / Play Store submission   | All above complete   | Standard store submission process                   |

---

## 19. Known Limitations & Roadmap

### Current Limitations

| Area                     | Limitation                                                              |
|--------------------------|-------------------------------------------------------------------------|
| Route algorithm          | Greedy nearest-neighbour; not optimal for > ~50 pickups                 |
| Conference allowlist     | Uploaded via Supabase SQL Editor only — no admin UI yet                 |
| Driver GPS tracking      | Live position shown on map; not stored to `profiles.location` server-side |
| Multiple drivers         | One driver per event; no multi-driver splitting                         |
| iOS deep links           | Entitlements file requires manual Xcode wiring before release           |
| Offline support          | No offline mode; all features require a network connection              |
| FCM token refresh        | Token only updated on login/join; OS-triggered token rotations unhandled|
| In-app notifications     | Push only (FCM); no foreground notification overlay                     |

### Roadmap (not committed)

- Live driver location stored to `profiles.location` for admin monitoring
- Admin UI for uploading conference email allowlists
- Multi-driver support with automatic load balancing
- 2-opt / OR-Tools route optimisation for large events
- FCM `onTokenRefresh` listener to keep tokens current
- Foreground notification overlay (in-app alerts)
- Event templates (recurring events pre-filled)
- Passenger notes on pickup requests (gate code, accessibility needs)
- Web admin dashboard for org management

---

*This whitepaper describes the system as built at the version indicated in the version table above. It is stored in the repository root (`WHITEPAPER.md`) and should be updated alongside any significant change to the system described here.*
