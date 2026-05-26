# Rover Engineer Completion Todo

This is the build-to-completion checklist for Rover, a Flutter + Supabase event pickup management app. It is intended as an engineer handoff: work through the phases in order, keep the database bootstrap authoritative, and do not mark a phase complete until its acceptance checks pass on a fresh environment.

## Product Target

Rover should ship as a multi-tenant mobile app for organisations that coordinate transport to events.

The completed app must support:

- Admins creating organisations, events, drivers, invite links/QR codes, join approvals, and member management.
- Attendees joining an organisation, browsing events, subscribing, requesting GPS pickup, and tracking driver ETA.
- Drivers viewing assigned events, starting an optimised route, updating pickup status, and using a live map.
- Secure tenant isolation through Supabase RLS and SECURITY DEFINER RPCs.
- Push notifications for pickup and organisation workflow events.
- Android and iOS builds with documented environment setup.

## Phase 0: Establish the Baseline

### 0.1 Confirm the current intended architecture

- Verify `front/roverfront` is the only active client application.
- Verify `supabase/schema_restore.sql` is the canonical bootstrap, or replace it with one clearly named canonical schema file.
- Verify edge functions live only under `supabase/functions`.
- Remove or document legacy artifacts that could confuse setup, including deleted or old Python/database files.

Acceptance criteria:

- A new engineer can identify the active app, schema, and functions in under 5 minutes from `README.md`.
- No setup path points to stale files.

### 0.2 Create a reproducible local/dev setup

- Add or update setup instructions for Flutter SDK, Dart defines, Supabase project setup, Firebase setup, and edge function secrets.
- Document required Dart defines: `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Document required Supabase secrets: service-role key, Firebase service account JSON, and internal notification token.
- Add a smoke-test checklist for fresh Supabase bootstrap, Flutter launch, login, org creation, and event creation.

Acceptance criteria:

- Fresh checkout can be configured from docs alone.
- `flutter pub get`, `flutter analyze`, and an app launch succeed.
- Fresh Supabase bootstrap creates all tables, RLS policies, RPCs, triggers, and indexes required by the app.

## Phase 1: Security and Data Correctness

### 1.1 Finalise database bootstrap and migrations

- Consolidate schema drift between `supabase/schema.sql`, `supabase/schema_restore.sql`, and `schema_v3` through `schema_v7`.
- Ensure these RPCs exist and are covered by setup docs:
  - `create_organisation_and_admin`
  - `join_organisation`
  - `join_organisation_with_code`, if still supported
  - `get_org_from_token`
  - `reset_org_token`
  - `search_organisations`
  - `approve_join_request`
  - `reject_join_request`
- Ensure required extensions are enabled, including PostGIS and any search extensions used.
- Add unique constraints for duplicate-sensitive workflows:
  - one event subscription per user/event
  - one active pickup request per user/event, or a deliberate replacement policy
  - invite token/code uniqueness

Acceptance criteria:

- Applying the canonical schema to an empty Supabase project succeeds without manual patching.
- All Flutter service calls map to existing tables/RPCs/columns.
- Duplicate subscription and pickup attempts fail safely.

### 1.2 Harden tenant isolation

- Review every table for RLS coverage.
- Lock `event_subscriptions` inserts to the caller's org and active events.
- Lock `pickup_requests` inserts to the caller's org, own user ID, subscribed or eligible event, and active event.
- Restrict driver updates to pickup rows for events assigned to that driver.
- Restrict admin event/member operations to the admin's own organisation.
- Ensure users cannot update `profiles.role`, `profiles.org_id`, or another user's profile directly.

Acceptance criteria:

- Cross-org reads, inserts, updates, and deletes fail under anon/user tokens.
- A malicious client cannot self-promote to admin or driver.
- RLS tests or documented SQL/manual checks cover user, driver, admin, and unauthenticated cases.

### 1.3 Secure edge functions

- Require trusted invocation for `send-notification`.
- Ensure `schedule-pickup` validates caller identity, assigned driver status, event org, event status, and input coordinates.
- Use service-role credentials only inside edge functions and only after caller validation.
- Return structured error responses with non-sensitive messages.
- Add internal token validation if one edge function calls another.

Acceptance criteria:

- Direct arbitrary client calls to `send-notification` are rejected.
- Only the assigned driver or authorised admin can schedule a pickup route.
- Function logs include enough context to debug failures without leaking tokens or PII.

## Phase 2: Core Workflow Completion

### 2.1 Authentication and onboarding

- Verify register, email confirmation, login, forgot password, and reset password flows on Android and iOS.
- Ensure deep-link invite tokens survive app restarts and email-confirmation round trips.
- After organisation join or creation, register the FCM token immediately.
- Handle users with `org_id = null` by routing them back to organisation setup.
- Add clear errors for invalid/expired invite tokens, duplicate membership, rejected conference allowlist, and pending join request.

Acceptance criteria:

- New admin can register, create an org, and land on the admin dashboard.
- New user/driver can join via QR/deep link and land on the correct dashboard.
- New user/driver can request to join via search and proceed after approval.
- FCM token is saved without requiring logout/login.

### 2.2 Admin event and organisation management

- Complete create, edit, cancel, list, and detail views for events.
- Add venue coordinate selection UX; avoid requiring admins to manually paste lat/lon as the only path.
- Complete driver assignment with same-org driver filtering.
- Complete member list with role, phone, joined date, and empty/error/loading states.
- Complete invite management:
  - QR display
  - share link
  - token reset
  - pending join requests
  - approve/reject actions
- Implement conference allowlist management in-app, or clearly defer it behind a documented admin-only SQL/setup path.

Acceptance criteria:

- Admin can run the full event lifecycle without leaving the app.
- Driver assignment cannot select users outside the organisation.
- Invite reset invalidates old QR/share links.
- Join request list updates reliably after approval/rejection.

### 2.3 Attendee event and pickup flow

- Complete event browse, search, detail, subscription, unsubscribe, pickup request, pickup cancellation, and ETA display.
- Add filters for event name, type, and date.
- Handle location permission denied, permanently denied, unavailable GPS, and invalid coordinates.
- Prevent pickup requests for cancelled/past events.
- Show current pickup status clearly: pending, en route, completed, cancelled if supported.

Acceptance criteria:

- Attendee can subscribe to an event, request pickup, cancel before completion, and watch status updates.
- Duplicate pickup requests are blocked in UI and database.
- Completed pickups disappear from active ETA UI but remain available where history is expected.

### 2.4 Driver route and map flow

- Complete assigned event list.
- Complete route start flow and map view.
- Persist pickup order, ETA, en-route status, completed status, and driver location updates.
- Show pickup names/phones without exposing FCM tokens or unrelated profile fields.
- Add a clear "next stop" interaction and safe completion confirmation.
- Handle no pickups, cancelled event, missing location permission, failed route scheduling, and offline/retry states.

Acceptance criteria:

- Driver can open an assigned event, start the route, mark riders en route/completed, and see the next stop update.
- Attendee UI reflects driver status in real time.
- Driver cannot mutate pickup rows for unassigned events.

## Phase 3: Notifications and Realtime

### 3.1 Complete push notification triggers

- Notify driver when a route is assigned or pickup requests are ready.
- Notify attendee when pickup is scheduled.
- Notify attendee when driver marks them en route.
- Notify next attendee when the previous pickup is completed, if supported by the route model.
- Notify user when a join request is approved or rejected.
- Notify organisation users when a new event is published, if this remains a product requirement.
- Notify subscribed users when an event is edited or cancelled.

Acceptance criteria:

- Each business event triggers at most one notification per intended recipient.
- Notification failures are logged and retryable where appropriate.
- Users without FCM tokens do not break the workflow.

### 3.2 Realtime state consistency

- Confirm realtime subscriptions are scoped by org/event/user.
- Refresh profile cross-reference maps when pickup rows or join requests change.
- Add fallback refresh after mutations so UI does not rely solely on websocket delivery.
- Unsubscribe channels on dispose to avoid leaks.

Acceptance criteria:

- Admin join request list updates after a new request.
- Driver pickup list updates when attendees request/cancel pickups.
- Attendee ETA/status updates after driver actions.
- Reopening screens shows correct state even if realtime missed an event.

## Phase 4: Performance and Scale

### 4.1 Add pagination and debouncing

- Debounce organisation search input.
- Debounce event search input.
- Paginate or range-fetch:
  - events
  - members
  - pickup requests
  - join requests
  - invite codes
- Add loading-more and empty-state UI.

Acceptance criteria:

- Lists remain responsive with 1,000+ rows in a test dataset.
- Search results correspond to the latest query only.

### 4.2 Add database indexes

- Add indexes for tenant-scoped queries:
  - `profiles(org_id, role)`
  - `events(org_id, event_date, status)`
  - `events(assigned_driver_id, status, event_date)`
  - `event_subscriptions(event_id, user_id)`
  - `pickup_requests(event_id, pickup_order)`
  - `pickup_requests(user_id, event_id, status)`
  - `org_join_requests(org_id, status, created_at)`
- Add search indexes for organisation/event search, including trigram GIN indexes if using fuzzy search.
- Review query plans for high-traffic screens.

Acceptance criteria:

- Common dashboard queries use indexes.
- Search is acceptably fast under realistic data volume.

### 4.3 Make route persistence transactional

- Replace per-row route updates with a single transactional RPC or SQL function.
- Return ordered route data from the same transaction.
- Define behavior for partial failures, cancelled requests during scheduling, and completed pickups.

Acceptance criteria:

- Route scheduling cannot leave half-updated pickup order/ETA rows.
- Failed route scheduling leaves previous stable state intact.

## Phase 5: UX, Design, and Accessibility

### 5.1 Apply the design system consistently

- Audit screens against `Design.md`.
- Use the Rover teal/amber palette consistently.
- Remove inconsistent legacy styling.
- Keep cards, inputs, buttons, status chips, and map overlays consistent.
- Avoid contradictory UI copy, especially around conference restrictions and invite behavior.

Acceptance criteria:

- Login, onboarding, admin, driver, attendee, and guide screens feel like one product.
- UI copy matches `ROVER_USER_GUIDE.md`.

### 5.2 Complete app states

- Add clear loading, empty, error, retry, offline, and success states to every networked screen.
- Prevent double-submits on forms and mutations.
- Add confirmation dialogs for destructive actions: cancel event, reset invite token, reject request, cancel pickup.
- Add input validation messages close to fields.

Acceptance criteria:

- No screen gets stuck with a spinner after an error.
- Users can recover from common failures without restarting the app.

### 5.3 Accessibility and mobile polish

- Check text scaling, contrast, tap target sizes, safe areas, keyboard behavior, and screen reader labels.
- Test on small Android, large Android, iPhone SE-size, and modern iPhone-size screens.
- Ensure map overlays do not block essential controls.

Acceptance criteria:

- App remains usable with larger text settings.
- All primary actions are reachable and labelled.

## Phase 6: Testing

### 6.1 Flutter test coverage

- Add unit tests for services where Supabase can be mocked or wrapped.
- Add widget tests for login, register, org setup, event detail, admin event form, and driver pickup list.
- Add validation tests for date, email, password, phone, coordinates, and role selection.

Acceptance criteria:

- Critical form and routing behavior is covered by automated tests.
- `flutter test` passes locally.

### 6.2 Supabase and RLS tests

- Add SQL tests or documented reproducible scripts for RLS policies.
- Test with anon, user, driver, admin, cross-org user, and service-role contexts.
- Test RPCs for success and failure paths.

Acceptance criteria:

- Tenant-isolation regressions are caught before release.
- RPC failure messages are clear enough for the app to display or map.

### 6.3 End-to-end acceptance testing

Run these scenarios before declaring the app complete:

- Admin registers, creates org, creates event, invites driver and attendee.
- Driver joins by QR/deep link and appears in admin driver assignment list.
- Attendee joins by QR/deep link, subscribes to event, requests pickup.
- Admin assigns driver to event.
- Driver starts route and marks attendee en route/completed.
- Attendee sees ETA/status changes.
- Admin cancels event and affected users see correct state.
- Search join request is approved/rejected.
- Conference allowlist blocks unauthorised email and allows authorised email.
- Old invite token fails after reset.

Acceptance criteria:

- All scenarios pass on a fresh database.
- Failures are filed as tickets with reproduction steps.

## Phase 7: Release Readiness

### 7.1 Android and iOS build setup

- Confirm Android package name, app label, icons, permissions, Firebase config, and signing.
- Confirm iOS bundle ID, display name, icons, permissions, Firebase config, associated domains/deep links, and signing.
- Verify required permissions:
  - location while in use
  - notifications
  - camera for QR scanning
  - internet/network access
- Remove debug-only fallbacks from release builds where appropriate.

Acceptance criteria:

- Android release build installs and runs.
- iOS release/archive build succeeds.
- Deep links and QR joins work on device.

### 7.2 Observability and support

- Add structured logs around auth, onboarding, route scheduling, notifications, and payment/entitlement hooks if added later.
- Add a support/contact path or feedback screen if product scope requires it.
- Document common operational checks for Supabase functions and FCM.

Acceptance criteria:

- Production issues can be diagnosed from logs without direct database inspection for every case.
- Support can guide users through common setup and permission problems.

### 7.3 Documentation closure

- Update `README.md` with current setup and release instructions.
- Update `ROVER_USER_GUIDE.md` for final user-facing behavior.
- Update `WHITEPAPER.md` architecture/version history only where implementation changed.
- Keep this todo or `IMPLEMENTATION_BACKLOG.md` updated with completed/deferred items.

Acceptance criteria:

- Docs match the actual app.
- No user guide section promises functionality that is missing or intentionally deferred.

## Optional Post-MVP Work

These should not block the core release unless the business requires them:

- Billing, subscriptions, trials, entitlements, and usage quotas.
- Analytics dashboard for attendance, pickup completion, ETA reliability, and engagement.
- Driver/attendee feedback and ratings.
- Advanced route optimisation using external routing APIs.
- Multi-organisation membership per user.
- Admin bulk import/export for members and conference allowlists.
- In-app notification preferences.
- Support/helpdesk integration.

## Completion Definition

Rover is complete when:

- A new organisation can run a real pickup event end to end with admin, driver, and attendee roles.
- Tenant isolation and privileged mutations are enforced server-side.
- Push notifications, realtime updates, and route scheduling work on real devices.
- Android and iOS builds are reproducible.
- Critical workflows have automated or documented acceptance tests.
- Setup, user guide, and architecture docs match the shipped implementation.
