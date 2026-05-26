# Rover Current Engineering Todo

This file is the active continuation checklist after comparing `ENGINEER_COMPLETION_TODO.md` with the current repo. Use `ENGINEER_COMPLETION_TODO.md` as the broad completion brief, and use this file for the next actionable engineering work.

Assessment date: 2026-05-25

## Repo Assessment Snapshot

### Implemented or Mostly Implemented

- Active architecture is now clear: Flutter app in `front/roverfront`, Supabase database/RLS/RPCs in `supabase/schema_restore.sql`, and Edge Functions in `supabase/functions`.
- Legacy Flask/database artifacts are removed from the active path and `README.md` points at the Flutter + Supabase stack.
- Canonical schema includes organisations, profiles, invites, events, subscriptions, pickup requests, conference allowlist, join requests, RLS policies, RPCs, triggers, uniqueness constraints, PostGIS, `pg_trgm`, and scale indexes.
- Security hardening is substantially implemented:
  - profile self-update cannot mutate role/org
  - subscription/pickup inserts are org and active-event scoped
  - driver pickup updates are constrained to assigned active events
  - admin policies are org-scoped
  - `send-notification` requires an internal token
  - `schedule-pickup` validates assigned driver, event status, event id, and coordinates before service-role writes
- Route persistence is transactional through `persist_pickup_route`.
- Admin workflow exists for org creation, event create/edit/cancel, driver assignment, attendees, members, QR/share invite, token reset, pending join requests, approval/rejection, access policy settings, and single-email allowlist management.
- Attendee workflow exists for event browse/search/filter, event detail, subscribe/unsubscribe, pickup request, pickup cancellation, and live pickup status/ETA card.
- Driver workflow exists for assigned events, route scheduling, pickup status transitions, map view, and best-effort location persistence.
- Notification workflow functions now exist:
  - `send-notification`
  - `schedule-pickup`
  - `update-pickup-status`
  - `review-join-request`
  - `notify-event-subscribers`
- Manual acceptance and RLS regression checklists exist under `docs/`.
- Basic Flutter tests exist, mostly validation-focused plus a couple of widget tests.

### Important Remaining Gaps

- Local verification is still unresolved. Prior `flutter analyze` / `flutter test` attempts hung silently in this environment, and `deno` is not installed.
- Fresh Supabase bootstrap from `supabase/schema_restore.sql` still needs a live empty-project verification.
- New Edge Functions need deployment and live invocation tests with real Supabase secrets.
- Notification triggers cover the main pickup/join/event edit flows, but durable idempotency/logging is not implemented.
- Driver assignment and new-event-published notifications from the broad handoff are not implemented.
- Admin event dialog now supports venue coordinates, but it still needs analyzer/device verification.
- Driver location is persisted to `profiles.location` and shown to attendees on an active pickup, but it still needs RLS/device verification.
- Service methods now support bounded range fetching; load-more UI is still deferred.
- Automated RLS regression tests are not present.
- Tests are still light on production-widget and integration-style coverage.
- Android/iOS release builds, signing, deep links, permissions, and Firebase delivery have not been verified.
- User-facing docs still need to be synchronized with the implemented allowlist, cancellation, notification, and location behavior.

## Priority 0: Verification and Canonical Baseline

### TODO P0.1: Get local toolchain verification to complete

- Run `flutter pub get` from `front/roverfront`.
- Run `flutter analyze`.
- Run `flutter test`.
- If commands hang again, capture the hanging command, environment symptoms, and process state in this file.
- Install or provide `deno`/Supabase function check path if Edge Function type checking is required locally.
- 2026-05-26 note: `flutter analyze` was attempted again from `front/roverfront`; it produced no output and did not return, so the spawned PowerShell/cmd analyzer process was stopped.

Acceptance criteria:

- Verification commands complete or the blocker is documented with reproduction steps.
- Analyzer/test failures are fixed or listed as concrete follow-up tasks.

### TODO P0.2: Verify fresh database bootstrap

- Apply `supabase/schema_restore.sql` to an empty Supabase project.
- Confirm all Flutter service references map to existing tables, columns, policies, functions, and triggers.
- Confirm canonical schema includes:
  - `org_email_allowlist`
  - `org_join_requests.requested_role`
  - `organisations.org_token`
  - `organisations.join_policy`
  - `organisations.driver_join_policy`
  - `organisations.searchable`
  - pickup uniqueness
  - transactional route RPC
  - all token/search/join-request RPCs

Acceptance criteria:

- A fresh Supabase project can be bootstrapped from `schema_restore.sql` alone.
- No manual SQL patching is required before the Flutter app can run.

### TODO P0.3: Deploy and smoke-test Edge Functions

- Deploy:
  - `send-notification`
  - `schedule-pickup`
  - `update-pickup-status`
  - `review-join-request`
  - `notify-event-subscribers`
- Set required Supabase secrets:
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `GOOGLE_SERVICE_ACCOUNT_JSON`
  - `INTERNAL_NOTIFY_TOKEN`
- Smoke-test success and failure paths for each function.

Acceptance criteria:

- Direct client calls to `send-notification` are rejected without the internal token.
- Assigned driver can schedule and update pickups.
- Unassigned driver/user cannot mutate route or pickup status.
- Join review and event subscriber notifications do not expose FCM tokens to clients.

## Priority 1: Product Workflow Gaps

### TODO P1.1: Add venue coordinate selection

- Status: implemented on 2026-05-26, pending Flutter analyzer/device verification.
- Added optional latitude/longitude fields to the admin event dialog.
- Added a "Use Current Location" action using device GPS.
- `EventService.createEvent()` already persists coordinates.
- Extended `EventService.updateEvent()` to update `location` when coordinates are provided.

Acceptance criteria:

- Admins do not need to source lat/lon outside the app.
- Event location data can support future map/route UX.

### TODO P1.2: Complete attendee live driver tracking

- Status: implemented on 2026-05-26, pending Flutter analyzer/device verification.
- Added `PickupService.listenToDriverLocation(driverId)` for realtime driver profile location updates.
- Added an attendee-side driver location panel/map inside `EventDetailPage` when a pickup is active and a driver is assigned.
- Keeps a fallback message when the driver has not shared a location yet.
- Confirm RLS allows only appropriate same-org attendees to read the assigned driver's location.

Acceptance criteria:

- Driver location persisted from `DriverMapPage` is visible to the relevant attendee workflow.
- Attendee tracking does not expose unrelated driver/profile data.

### TODO P1.3: Finish notification coverage decisions

- Decide whether these handoff notifications are MVP requirements:
  - driver notified when assigned to an event
  - driver notified when pickup requests are ready
  - organisation users notified when a new event is published
- Implement required ones through dedicated Edge Functions or safe server-side flows.
- Add durable idempotency/logging if exact-once business notification semantics are required.

Acceptance criteria:

- Every MVP notification trigger is either implemented or explicitly deferred.
- Retries do not spam users for the same business event.

## Priority 2: Scale and Data Access

### TODO P2.1: Add pagination/range fetching

- Status: service-level defaults implemented on 2026-05-26, UI load-more still deferred.
- Added optional `offset`/`limit` parameters with default bounded ranges for:
  - events
  - event search
  - event attendees
  - drivers
  - driver events
  - members
  - pending join requests
  - allowlist rows
  - pickup requests
  - legacy invite codes
- Remaining UI work: add load-more or paged controls where lists can grow.

Acceptance criteria:

- Large orgs do not fetch unbounded lists on initial screen load.
- Search/list screens remain responsive with high row counts.

### TODO P2.2: Verify index usage

- After applying the canonical schema, inspect query plans for:
  - admin event list
  - attendee event browse/search
  - driver assigned event list
  - pickup list by event/order
  - pending join requests
  - org search
- Adjust indexes only if the planner misses critical paths.

Acceptance criteria:

- Common tenant-scoped queries use appropriate indexes.

## Priority 3: Security Regression Coverage

### TODO P3.1: Automate or script RLS checks

- Convert `docs/RLS_REGRESSION_CHECKS.md` into executable SQL or a repeatable manual harness.
- Cover:
  - cross-org event subscription rejection
  - cross-org pickup request rejection
  - profile self-promotion rejection
  - unassigned driver pickup update rejection
  - admin-only join approval/rejection
  - allowlist admin-only mutation

Acceptance criteria:

- Tenant isolation can be regression-tested without hand-inventing SQL every time.

## Priority 4: Tests and Release Readiness

### TODO P4.1: Expand Flutter tests

- Add production-widget tests where dependency setup allows:
  - org setup routing and pending request state
  - event detail pickup request/cancel state
  - admin event form validation
  - driver pickup status controls
- Add service-level tests behind wrappers/mocks if practical.

Acceptance criteria:

- Critical UI behavior is tested without relying only on copied validation doubles.

### TODO P4.2: Run end-to-end acceptance

- Use `docs/ACCEPTANCE_CHECKLIST.md` on a fresh database and real devices where possible.
- Include admin, driver, attendee, conference allowlist, notifications, realtime, invite reset, and cancellation flows.

Acceptance criteria:

- Release candidate pass/fail is reproducible.
- Failures are logged with steps and assigned priority.

### TODO P4.3: Verify mobile release configuration

- Android:
  - package id
  - app label/icons
  - permissions
  - Firebase config
  - signing
  - release build install
- iOS:
  - bundle id
  - display name/icons
  - permissions
  - Firebase config
  - associated domains/deep links
  - signing/archive

Acceptance criteria:

- Android and iOS release builds are reproducible and documented.

## Priority 5: Documentation Closure

### TODO P5.1: Sync user-facing docs

- Update `README.md` with any final setup/deployment verification results.
- Update `ROVER_USER_GUIDE.md` for:
  - attendee pickup cancellation
  - conference allowlist management
  - join approval behavior
  - notification behavior
  - driver location/ETA behavior
- Update `WHITEPAPER.md` only where implementation architecture changed.

Acceptance criteria:

- Docs do not promise missing behavior.
- A new engineer/operator can bootstrap, deploy, and accept the app from docs alone.

## Suggested Next Sprint

1. P0.1: Resolve local Flutter/Edge Function verification.
2. P0.2/P0.3: Fresh Supabase bootstrap plus Edge Function deployment smoke test.
3. P1.3: Decide and implement/defer the remaining non-core notification triggers.
4. P2.1: Add load-more UI on top of the bounded service methods where needed.
5. P3.1/P4.1: Convert RLS checks and critical UI flows into repeatable tests.
