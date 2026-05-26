# Rover Implementation Backlog

This backlog converts the audit into concrete implementation work ordered by impact vs effort.

## Sequencing

1. Phase 0: Production blockers (security + correctness)
2. Phase 1: Performance and reliability
3. Phase 2: UX closure and product completion
4. Phase 3: SaaS monetisation and scale

## Phase 0: Production Blockers

### ROV-001: Canonical database bootstrap and migration chain
- Priority: P0
- Effort: M
- Scope:
  - Define one authoritative bootstrap path for Supabase schema/migrations.
  - Ensure all required RPCs/tables/policies are included.
  - Update setup docs in [README.md](/C:/Users/ofone/Documents/JEHMNi/Rover/README.md).
- Touch points:
  - [supabase/schema.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema.sql)
  - [supabase/schema_v3_token_additions.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema_v3_token_additions.sql)
  - [supabase/schema_v4_conference_search.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema_v4_conference_search.sql)
  - [supabase/schema_v5_search_rpc.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema_v5_search_rpc.sql)
  - [supabase/schema_v6_fixes.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema_v6_fixes.sql)
  - [supabase/schema_v7_profile_security_hardening.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema_v7_profile_security_hardening.sql)
- Acceptance criteria:
  - Fresh project setup succeeds with one documented command flow.
  - `join_organisation`, `search_organisations`, join-request RPCs, and hardened policies exist post-setup.
  - README no longer implies `schema.sql` alone is sufficient.

### ROV-002: Register FCM token immediately after org join
- Priority: P0
- Effort: S
- Scope:
  - After successful org join, call `AuthService.registerFcmToken()`.
- Touch points:
  - [front/roverfront/lib/screens/org_setup_page.dart](/C:/Users/ofone/Documents/JEHMNi/Rover/front/roverfront/lib/screens/org_setup_page.dart)
  - [front/roverfront/lib/services/auth_service.dart](/C:/Users/ofone/Documents/JEHMNi/Rover/front/roverfront/lib/services/auth_service.dart)
- Acceptance criteria:
  - Joining an org writes `profiles.fcm_token` without requiring logout/login.
  - Whitepaper claim matches behavior.

### ROV-003: Harden RLS for subscriptions and pickup requests
- Priority: P0
- Effort: M
- Scope:
  - Tighten `WITH CHECK`/`USING` so inserts/updates are bound to caller org/event constraints.
  - Ensure users cannot create cross-org rows by guessing event IDs.
- Touch points:
  - [supabase/schema.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema.sql)
  - [supabase/schema_restore.sql](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/schema_restore.sql)
- Acceptance criteria:
  - Unauthorized cross-org insert/update attempts fail.
  - Driver status updates are restricted to assigned-driver events within org.

### ROV-004: Restrict `send-notification` to trusted callers
- Priority: P0
- Effort: M
- Scope:
  - Add explicit authz checks in edge function.
  - Validate caller context and allowed invocation paths.
- Touch points:
  - [supabase/functions/send-notification/index.ts](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/functions/send-notification/index.ts)
  - [supabase/functions/schedule-pickup/index.ts](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/functions/schedule-pickup/index.ts)
- Acceptance criteria:
  - Arbitrary client invocation is rejected.
  - Route-scheduler invocation still succeeds.

## Phase 1: Performance and Reliability

### ROV-005: Debounced org search UX
- Priority: P1
- Effort: S
- Scope:
  - Add debounce (e.g. 250–400ms) for org search input.
  - Prevent race-condition UI flicker from overlapping requests.
- Touch points:
  - [front/roverfront/lib/screens/org_setup_page.dart](/C:/Users/ofone/Documents/JEHMNi/Rover/front/roverfront/lib/screens/org_setup_page.dart)
- Acceptance criteria:
  - Search does not fire per keystroke.
  - Result list always corresponds to latest query.

### ROV-006: Paginate high-growth lists
- Priority: P1
- Effort: M
- Scope:
  - Add pagination/range fetches for events, members, requests.
  - Add UI “load more” or infinite-scroll pattern.
- Touch points:
  - [front/roverfront/lib/services/event_service.dart](/C:/Users/ofone/Documents/JEHMNi/Rover/front/roverfront/lib/services/event_service.dart)
  - [front/roverfront/lib/services/org_service.dart](/C:/Users/ofone/Documents/JEHMNi/Rover/front/roverfront/lib/services/org_service.dart)
  - Relevant admin/user screens.
- Acceptance criteria:
  - Large datasets (>1k rows) remain responsive.
  - Network payload and initial render time are reduced.

### ROV-007: Search index hardening (`pg_trgm` + GIN)
- Priority: P1
- Effort: S
- Scope:
  - Add trigram indexes for `organisations(name, city)` and event name search paths.
- Touch points:
  - Supabase migration SQL files.
- Acceptance criteria:
  - Search latency under load significantly improved.
  - Query plans show index usage.

### ROV-008: Transactional route persistence in `schedule-pickup`
- Priority: P1
- Effort: M
- Scope:
  - Replace per-row `Promise.all` updates with one transactional DB-side operation (RPC/SQL function).
  - Return explicit failure if any stop update fails.
- Touch points:
  - [supabase/functions/schedule-pickup/index.ts](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/functions/schedule-pickup/index.ts)
  - New SQL RPC in schema.
- Acceptance criteria:
  - No partial route writes.
  - Deterministic failure semantics with actionable errors.

## Phase 2: Product and UX Closure

### ROV-009: Share-tab messaging consistency
- Priority: P1
- Effort: S
- Scope:
  - Update admin copy so conference restrictions are clearly communicated.
- Touch points:
  - [front/roverfront/lib/screens/admin_home_page.dart](/C:/Users/ofone/Documents/JEHMNi/Rover/front/roverfront/lib/screens/admin_home_page.dart)
  - [ROVER_USER_GUIDE.md](/C:/Users/ofone/Documents/JEHMNi/Rover/ROVER_USER_GUIDE.md)
- Acceptance criteria:
  - No contradiction between admin UI and guide behavior.

### ROV-010: Implement planned notification triggers
- Priority: P1
- Effort: M
- Scope:
  - Next user alert when current pickup completed.
  - Join-request approved alert.
  - New event broadcast to org users.
- Touch points:
  - [supabase/functions/send-notification/index.ts](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/functions/send-notification/index.ts)
  - [supabase/functions/schedule-pickup/index.ts](/C:/Users/ofone/Documents/JEHMNi/Rover/supabase/functions/schedule-pickup/index.ts)
  - Relevant app services/screens.
- Acceptance criteria:
  - Triggers fire exactly once per business event.
  - Failures are observable and retryable.

### ROV-011: Admin allowlist upload UI (conference orgs)
- Priority: P2
- Effort: M
- Scope:
  - Build admin flow to upload/manage conference allowlist instead of SQL-editor dependency.
- Touch points:
  - Admin UI
  - `org_email_allowlist` table/RLS.
- Acceptance criteria:
  - Admin can upload, view, and revoke allowlist entries in-app.
  - Join flow respects uploaded allowlist without manual SQL.

## Phase 3: SaaS Monetisation and Scale

### ROV-012: Billing and entitlements foundation
- Priority: P1 (business), P2 (technical urgency)
- Effort: L
- Scope:
  - Add plans, subscriptions, entitlement checks, trial lifecycle.
  - Enforce feature gates in API + client.
- Acceptance criteria:
  - Tenant cannot access paid capabilities without entitlement.
  - Upgrade/downgrade paths are consistent.

### ROV-013: Usage metering and quotas
- Priority: P1 (business)
- Effort: M
- Scope:
  - Meter key resources per org (events, active riders, notifications, route runs).
  - Add quota enforcement and overage reporting.
- Acceptance criteria:
  - Metered usage is queryable and billable.
  - Over-limit behavior is explicit and user-friendly.

### ROV-014: Ops analytics and retention instrumentation
- Priority: P2
- Effort: M
- Scope:
  - Build admin analytics for attendance, pickup completion, ETA reliability.
  - Track activation/retention funnel and drop-off points.
- Acceptance criteria:
  - Metrics available per org and over time.
  - Dashboard supports product and GTM decisions.

## Suggested Sprint Breakdown

1. Sprint 1: ROV-001, ROV-002, ROV-003
2. Sprint 2: ROV-004, ROV-005, ROV-007
3. Sprint 3: ROV-006, ROV-008, ROV-009
4. Sprint 4: ROV-010, ROV-011
5. Sprint 5+: ROV-012, ROV-013, ROV-014

## Definition of Done (applies to all tickets)

1. Code implemented with tests for critical paths.
2. `flutter analyze` clean.
3. Relevant docs updated.
4. Security impact reviewed for auth/RLS/function changes.
5. Observability logs/metrics added for failure-prone flows.
