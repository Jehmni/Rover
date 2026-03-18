# Rover — Platform Whitepaper

> **Living document.** Each section is scoped to a specific component of the system.
> When a component changes, update only its section and increment the version table below.
> The rest of the document stays valid.

---

## Version History

| Version | Date       | Changed Section(s)          | Summary                                                |
|---------|------------|-----------------------------|--------------------------------------------------------|
| 1.0     | 2026-03-18 | All                         | Initial whitepaper — covers Phase A–C (multi-tenant, onboarding, token join, deep links) |

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
10. [Real-Time Updates](#10-real-time-updates)
11. [Deep Links & QR Codes](#11-deep-links--qr-codes)
12. [Conference Org Support](#12-conference-org-support)
13. [Notifications (FCM)](#13-notifications-fcm)
14. [Technology Stack](#14-technology-stack)
15. [Platform Support](#15-platform-support)
16. [Known Limitations & Roadmap](#16-known-limitations--roadmap)

---

## 1. Purpose & Problem Statement

Rover is a mobile platform that solves a coordination problem common to churches, conferences, schools, and other community organisations: **getting people to events when they don't have their own transport**.

Without Rover, an organiser must manually collect addresses, phone drivers individually, and figure out pickup order by hand. Drivers receive information piecemeal, often by WhatsApp message. Attendees don't know when the driver is coming. The entire process is slow, error-prone, and doesn't scale past a handful of attendees.

Rover replaces this with a structured, real-time flow:

- Attendees register their GPS pickup location through the app in seconds.
- The system computes an optimised pickup route automatically.
- Drivers follow a sorted, live-updated pickup list with ETAs.
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

| Role     | Can Do                                                                                              |
|----------|-----------------------------------------------------------------------------------------------------|
| `admin`  | Create and manage the organisation; create/edit/cancel events; assign drivers; manage join requests; reset invite token |
| `driver` | View events assigned to them; start route optimisation; mark pickups as completed                   |
| `user`   | Browse events in their org; subscribe to events; request a pickup; view live driver ETA             |

Roles are set server-side via SECURITY DEFINER RPCs. A client cannot self-promote to admin or driver by modifying a request.

---

## 4. System Architecture

```
┌─────────────────────────────────────────────────────┐
│                Flutter Mobile App                   │
│  Android + iOS                                      │
│  ┌──────────┐  ┌────────────┐  ┌─────────────────┐ │
│  │  Screens │  │  Services  │  │  Supabase client│ │
│  └──────────┘  └────────────┘  └─────────────────┘ │
└────────────────────────┬────────────────────────────┘
                         │ HTTPS / WebSocket
┌────────────────────────▼────────────────────────────┐
│                    Supabase                         │
│  ┌────────────┐  ┌──────────┐  ┌────────────────┐  │
│  │ PostgreSQL │  │ Auth     │  │ Realtime       │  │
│  │ + PostGIS  │  │ (JWT)    │  │ (WebSocket)    │  │
│  └────────────┘  └──────────┘  └────────────────┘  │
│  ┌────────────────────────────────────────────────┐ │
│  │ Edge Functions (Deno)                          │ │
│  │  schedule-pickup — route optimisation          │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────┐
│          Firebase Cloud Messaging (FCM)             │
│  Push notifications to driver & attendee devices    │
└─────────────────────────────────────────────────────┘
```

**Key design decisions:**

- The Flutter client communicates with Supabase only via the PostgREST API and SECURITY DEFINER RPCs. No privileged logic runs on the client.
- Route optimisation runs in a Deno Edge Function with service-role credentials, so it can read all pickup requests for an event regardless of RLS.
- Real-time updates use Supabase's built-in WebSocket channel (Postgres logical replication → client). No polling.
- Firebase is used only for push notifications. App state is always sourced from Supabase.

---

## 5. Database Schema

All tables live in the `public` schema of a single Supabase PostgreSQL instance. The PostGIS extension provides geographic data types and spatial queries.

### 5.1 Core Tables

#### `organisations`
The tenant boundary. Every piece of data is scoped to one organisation.

| Column      | Type        | Notes                                                    |
|-------------|-------------|----------------------------------------------------------|
| `id`        | uuid PK     | `gen_random_uuid()`                                      |
| `name`      | text        | Display name                                             |
| `city`      | text        | Optional                                                 |
| `country`   | text        | Optional                                                 |
| `org_type`  | text        | `church` / `conference` / `corporate` / `school` / `other` |
| `org_token` | uuid UNIQUE | Single-use invite token; powers QR code and share link   |
| `searchable`| boolean     | `true` = discoverable in search; `false` = hidden (conference default) |
| `created_at`| timestamptz |                                                          |

#### `profiles`
One row per authenticated user. `org_id` is NULL until the user completes org setup.

| Column      | Type              | Notes                                                   |
|-------------|-------------------|---------------------------------------------------------|
| `id`        | uuid PK           | FK → `auth.users(id)`                                   |
| `role`      | text              | `user` / `driver` / `admin`                             |
| `full_name` | text              |                                                         |
| `phone`     | text              | Optional                                                |
| `org_id`    | uuid              | FK → `organisations(id)`; NULL = no org yet             |
| `location`  | geography(POINT)  | Driver's last-known position (SRID 4326)                |
| `fcm_token` | text              | Firebase device token for push notifications            |
| `created_at`| timestamptz       |                                                         |

#### `events`
Created by admins. `org_id` and `admin_id` are auto-set by a BEFORE INSERT trigger.

| Column               | Type              | Notes                                      |
|----------------------|-------------------|--------------------------------------------|
| `id`                 | bigserial PK      |                                            |
| `org_id`             | uuid              | FK → `organisations(id)` (set by trigger)  |
| `name`               | text              |                                            |
| `description`        | text              | Optional                                   |
| `location`           | geography(POINT)  | Event venue (SRID 4326)                    |
| `location_name`      | text              | Human-readable venue label                 |
| `event_date`         | timestamptz       |                                            |
| `event_type`         | text              | Free-form label (e.g. "Sunday Service")    |
| `admin_id`           | uuid              | FK → `profiles(id)` (set by trigger)       |
| `assigned_driver_id` | uuid              | FK → `profiles(id)` (set by admin)         |
| `status`             | text              | `active` / `cancelled` / `completed`       |
| `created_at`         | timestamptz       |                                            |

#### `event_subscriptions`
Users register interest in events. Required before a pickup request can be made.

| Column      | Type        | Notes                            |
|-------------|-------------|----------------------------------|
| `id`        | bigserial PK|                                  |
| `event_id`  | bigint      | FK → `events(id)`                |
| `user_id`   | uuid        | FK → `profiles(id)`              |
| `created_at`| timestamptz |                                  |
| *(unique)*  |             | `(event_id, user_id)`            |

#### `pickup_requests`
A user's request for transport to a specific event, including their GPS pickup point and real-time routing data.

| Column           | Type              | Notes                                              |
|------------------|-------------------|----------------------------------------------------|
| `id`             | bigserial PK      |                                                    |
| `event_id`       | bigint            | FK → `events(id)`                                  |
| `user_id`        | uuid              | FK → `profiles(id)`                                |
| `pickup_location`| geography(POINT)  | User's GPS location (SRID 4326) — stored as WKT `POINT(lon lat)` |
| `pickup_order`   | int               | Set by route algorithm; 1 = first stop             |
| `eta_minutes`    | int               | Minutes from route start to this pickup            |
| `status`         | text              | `pending` / `en_route` / `completed`               |
| `created_at`     | timestamptz       |                                                    |

### 5.2 Org Membership Tables

#### `org_invites`
Legacy invite-code table. Still present in the schema for backward compatibility. The primary join mechanism is now `org_token` (QR/link).

#### `org_email_allowlist`
Conference orgs only. Each row is a permitted attendee email.

| Column      | Type        | Notes                                            |
|-------------|-------------|--------------------------------------------------|
| `id`        | bigserial PK|                                                  |
| `org_id`    | uuid        | FK → `organisations(id)`                         |
| `email`     | text        |                                                  |
| `claimed`   | boolean     | Set to `true` when the email is used to join     |
| `created_at`| timestamptz |                                                  |
| *(unique)*  |             | `(org_id, email)`                                |

#### `org_join_requests`
Search-fallback join flow. Users who can't find a QR/link request access; admin approves.

| Column      | Type        | Notes                                            |
|-------------|-------------|--------------------------------------------------|
| `id`        | bigserial PK|                                                  |
| `org_id`    | uuid        | FK → `organisations(id)`                         |
| `user_id`   | uuid        | FK → `auth.users(id)`                            |
| `status`    | text        | `pending` / `approved` / `rejected`              |
| `created_at`| timestamptz |                                                  |
| *(unique)*  |             | `(org_id, user_id)`                              |

### 5.3 Key RPCs (SECURITY DEFINER Functions)

| Function                             | Called By     | Purpose                                                        |
|--------------------------------------|---------------|----------------------------------------------------------------|
| `create_organisation_and_admin()`    | OrgSetupPage  | Creates org + claims admin role atomically                     |
| `join_organisation(token, role)`     | OrgSetupPage  | Validates token, sets org_id + role on profile; checks conference allowlist |
| `reset_org_token(org_id)`            | Admin Share tab | Generates a new UUID token; invalidates all existing QR/links |
| `get_org_from_token(token)`          | WelcomePage   | Public lookup (granted to `anon`) — resolves org name pre-auth |
| `approve_join_request(request_id)`  | Admin Share tab | Sets org_id on the user's profile server-side                 |
| `reject_join_request(request_id)`   | Admin Share tab | Marks request as rejected                                     |
| `join_organisation_with_code(code)` | (legacy)      | Invite-code join — kept for backward compatibility            |
| `generate_invite_code(role)`        | (legacy)      | Admin generates code — kept for backward compatibility        |
| `get_my_org_id()`                   | RLS policies  | Helper — reads caller's org without recursion                 |
| `get_my_role()`                     | RLS policies  | Helper — reads caller's role without recursion                |

### 5.4 Database Triggers

| Trigger                 | Table       | When         | Effect                                                        |
|-------------------------|-------------|--------------|---------------------------------------------------------------|
| `before_event_insert`   | `events`    | BEFORE INSERT | Auto-sets `org_id` (from caller's profile) and `admin_id` (auth.uid()) |
| `on_auth_user_created`  | `auth.users`| AFTER INSERT  | Creates minimal profile row (`role='user'`, `org_id=NULL`)   |

---

## 6. Security Model

Rover's security is enforced at the database layer, not the application layer. The client app is treated as untrusted.

### 6.1 Row Level Security (RLS)

RLS is enabled on every table. Policies ensure:

- **Tenant isolation**: users can only read/write data that belongs to their own organisation.
- **Role enforcement**: only admins can insert events, manage members, and approve join requests.
- **Self-only writes**: users can only modify their own profile, subscriptions, and pickup requests.

RLS policies use two SECURITY DEFINER helper functions — `get_my_org_id()` and `get_my_role()` — to read the caller's profile. These helpers prevent infinite recursion that would occur if policies queried the `profiles` table directly.

### 6.2 SECURITY DEFINER RPCs

All privileged mutations — org creation, token joins, request approvals, role assignment — run as SECURITY DEFINER functions owned by the `postgres` role. This means:

- The database validates the operation server-side regardless of what the client sends.
- A client cannot call `UPDATE profiles SET role = 'admin'` directly; RLS blocks it.
- A client cannot create an org and declare themselves admin in two separate calls; the RPC does both atomically.

### 6.3 Invite Token Security

The invite token (`org_token`) is a UUID (128 bits of entropy). A brute-force attack against the join endpoint would require ≈ 2¹²⁸ guesses. Tokens can be rotated instantly by the admin, invalidating all previously shared QR codes and links.

### 6.4 Conference Gating

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
    ├─ Has session ──► destinationForRole()
    │                      ├─ no_org  ──► OrgSetupPage
    │                      ├─ admin   ──► AdminHomePage
    │                      ├─ driver  ──► DriverHomePage
    │                      └─ user    ──► UserHomePage
    │
    └─ No session ──► LoginPage
                          │
                          ├─ Sign in ──► (as above)
                          │
                          └─ "Create an account" ──► WelcomePage
                                                          │
                              ┌───────────────────────────┤
                              │                           │
                    "I'm organising"           "I'm a driver" / "I'm attending"
                              │                           │
                         RegisterPage               RegisterPage
                         (role=admin)           (role=driver / user)
                              │                           │
                         OrgSetupPage               OrgSetupPage
                         (Tab A: Create)            (Tab B: Join)
                              │                           │
                        AdminHomePage          DriverHome / UserHome
```

### 7.1 Deep Link Onboarding

When a user taps a `rover.app/join/TOKEN` link before having an account:

1. The app intercepts the link via `app_links`.
2. `PendingLink.orgToken` stores the token across navigation.
3. WelcomePage resolves the org name via `get_org_from_token()` (granted to `anon`) and shows a banner: *"You've been invited to join [Org Name]"*.
4. The user selects their role, registers, and is taken to OrgSetupPage with the token pre-filled.
5. Tapping "Join Organisation" calls `join_organisation(token, role)` and routes to their home screen.

**Target: ≤ 5 taps from cold link to home screen.**

---

## 8. Event Management

### 8.1 Admin

Admins manage events from the Events tab of AdminHomePage:

- **Create**: name, date/time, description, venue name, type. The BEFORE INSERT trigger auto-assigns `org_id` and `admin_id`.
- **Edit**: update name, description, type, venue, date.
- **Cancel**: soft-delete via `status = 'cancelled'`. Cancelled events remain in the database but are hidden from non-admin users.
- **Assign driver**: dropdown of all driver-role users in the org. Sets `assigned_driver_id`.
- **View attendees**: list of subscribed users with name and phone.

### 8.2 Users

From UserHomePage, users can browse and search events by name, type, and date. Tapping an event opens EventDetailPage where they can:

- **Subscribe / Unsubscribe** — toggle attendance registration.
- **Request Pickup** — only available after subscribing. Submits the user's current GPS location as a pickup request.
- **View ETA** — once the driver starts the route, a live ETA card appears showing pickup order and countdown.

---

## 9. Pickup & Route Optimisation

### 9.1 Pickup Request

When a user taps "Request Pickup":

1. The app requests location permission and reads GPS (high-accuracy mode).
2. Coordinates are validated (latitude: −90 to 90; longitude: −180 to 180).
3. An existing pending request for the same event is checked — duplicates are blocked.
4. A row is inserted into `pickup_requests` with `pickup_location = 'POINT(lon lat)'`.

### 9.2 Route Computation

When the assigned driver taps "Start Route":

1. The app reads the driver's current GPS position.
2. A request is sent to the `schedule-pickup` Supabase Edge Function (Deno, service-role credentials).
3. The function:
   - Fetches all pending pickup requests for the event (bypasses RLS via service role).
   - Runs a **greedy nearest-neighbour algorithm** starting from the driver's position.
   - Assigns `pickup_order` (1 = next stop) and `eta_minutes` to each row in `pickup_requests`.
   - Sends an FCM push notification to the first user: *"Your driver is on the way"*.
   - Returns the ordered list to the app.
4. The driver sees a sorted pickup list. As they mark each pickup "Done" (`status = 'completed'`), the list updates in real time.

### 9.3 Algorithm Note

The current implementation uses O(n²) nearest-neighbour — adequate for the typical fleet size (< 50 pickups per event). Future versions may upgrade to a 2-opt or OR-Tools optimiser for larger events.

---

## 10. Real-Time Updates

Rover uses Supabase Realtime (PostgreSQL logical replication → WebSocket) for two live streams:

| Stream                        | Subscriber    | Updates When                                |
|-------------------------------|---------------|---------------------------------------------|
| `listenToPickupUpdates(event)`| Driver screen | Any row in `pickup_requests` for the event changes (order, ETA, status) |
| `listenToMyPickup(event)`     | User screen   | The current user's own `pickup_requests` row changes |

No polling. Changes in the database propagate to all connected clients within ~100ms.

---

## 11. Deep Links & QR Codes

Every organisation has a single `org_token` (UUID). This token is used in two ways:

- **QR code** — rendered in the admin Share tab via `qr_flutter`. Scanning with any QR reader (or the in-app scanner) opens `rover.app/join/TOKEN` in a browser or directly in the app.
- **Share link** — `https://rover.app/join/TOKEN`. Shared via the native share sheet (using `share_plus`) or copied to clipboard.

Both encode the same token. The admin can reset the token at any time (invalidating all outstanding QR codes and links instantly).

### 11.1 Platform Deep Link Config

| Platform | Mechanism                                      | Status                              |
|----------|------------------------------------------------|-------------------------------------|
| Android  | `intent-filter` with `android:autoVerify=true` in `AndroidManifest.xml` | Configured |
| iOS      | `applinks:rover.app` in `Runner.entitlements` | File created; must be wired in Xcode Build Settings before release |

### 11.2 Join Methods (in priority order)

1. **QR scan** — camera icon in OrgSetupPage Tab B; MobileScanner reads the code and auto-fills token.
2. **Link paste** — text field accepts full URL (`rover.app/join/UUID`) or bare UUID token; parsed client-side.
3. **Search fallback** — user searches orgs by name/city; taps "Request"; admin approves from Share tab.

---

## 12. Conference Org Support

Conference-type organisations differ from community orgs in three ways:

| Feature               | Community org (`church`, etc.)     | Conference org                               |
|-----------------------|------------------------------------|----------------------------------------------|
| Discoverable in search| Yes (`searchable = true`)          | No (`searchable = false`)                    |
| Who can join          | Anyone with the token              | Only emails on the `org_email_allowlist`     |
| Email slot reuse      | N/A                                | Each email can only be claimed once          |

**Admin workflow:**

1. Create org with `org_type = 'conference'`.
2. Upload attendee emails to `org_email_allowlist` (via SQL or a future admin UI).
3. Share the QR code / link as normal.
4. Attendees who tap the link are checked against the allowlist; their slot is marked `claimed`.

---

## 13. Notifications (FCM)

Firebase Cloud Messaging is integrated for push notifications. FCM tokens are stored in `profiles.fcm_token` and updated each time a user logs in.

Current notification triggers (implemented in Edge Functions):

| Trigger                   | Recipient     | Message                          |
|---------------------------|---------------|----------------------------------|
| Driver starts route       | First user    | "Your driver is on the way"      |

Future triggers (roadmap):

| Trigger                   | Recipient     | Message                          |
|---------------------------|---------------|----------------------------------|
| Driver marks pickup done  | Next user     | "You're next — driver is close"  |
| Event created             | All org users | "New event: [name] on [date]"    |
| Join request approved     | User          | "You've been added to [org]"     |

---

## 14. Technology Stack

| Layer              | Technology                          | Version / Notes                          |
|--------------------|-------------------------------------|------------------------------------------|
| Mobile app         | Flutter                             | Dart; targets Android and iOS            |
| Backend / DB       | Supabase (PostgreSQL + PostGIS)     | Multi-tenant via RLS                     |
| Auth               | Supabase Auth                       | Email/password; JWT                      |
| Real-time          | Supabase Realtime                   | WebSocket; logical replication           |
| Edge functions     | Supabase Edge Functions (Deno)      | Route optimisation (`schedule-pickup`)   |
| Push notifications | Firebase Cloud Messaging            | Android + iOS                            |
| Deep links         | `app_links` ^6.3.4                  | Cold-start + warm link handling          |
| QR display         | `qr_flutter` ^4.1.0                 | Admin Share tab                          |
| QR scan            | `mobile_scanner` ^6.0.8             | In-app camera scan on join screen        |
| Native share       | `share_plus` ^10.1.4                | OS share sheet for invite link           |
| Geo storage        | PostGIS geography(POINT, 4326)      | Pickup locations, event venues           |

---

## 15. Platform Support

| Platform | Status        | Notes                                                                   |
|----------|---------------|-------------------------------------------------------------------------|
| Android  | Supported     | Deep links configured. FCM supported.                                   |
| iOS      | Supported     | Camera permission set. Entitlements file created; Xcode wiring required before App Store release. |
| Web      | Not targeted  | No web-specific UI; Supabase access would work but no responsive layout |
| Windows  | Dev only      | Used for development; plugin stubs generated but not shipped            |

---

## 16. Known Limitations & Roadmap

### Current Limitations

| Area                  | Limitation                                                               |
|-----------------------|--------------------------------------------------------------------------|
| Route algorithm       | Greedy nearest-neighbour; not optimal for > ~50 pickups                  |
| Conference allowlist  | Uploaded via SQL only — no admin UI yet                                  |
| Driver tracking       | Driver location is read once at route start; no live GPS tracking        |
| Multiple drivers      | One driver per event; no multi-driver splitting                          |
| iOS deep links        | Entitlements file requires manual Xcode wiring before release            |
| Offline support       | No offline mode; requires network connection                             |

### Roadmap (not committed)

- Admin UI for uploading conference email allowlists
- Live driver location tracking (background GPS stream)
- Multi-driver support with automatic load balancing
- 2-opt / OR-Tools route optimisation for large events
- In-app notifications (foreground; not just FCM)
- Event templates (recurring events pre-filled)
- Passenger notes on pickup requests (gate code, accessibility needs)
- Web admin dashboard for org management

---

*This whitepaper describes the system as built at the version indicated in the version table above. It is stored in the repository root (`WHITEPAPER.md`) and should be updated alongside any significant change to the system described here.*
