# Rover RLS Regression Checks

These checks document the security cases that must keep passing as the schema evolves. They are written as a manual test plan because the repo does not yet have a local Supabase test harness.

Run these against a non-production Supabase project bootstrapped from `supabase/schema_restore.sql`.

## Test Actors

Create or identify these users:

- `admin_a`: admin of organisation A
- `driver_a`: driver in organisation A
- `user_a`: attendee in organisation A
- `admin_b`: admin of organisation B
- `driver_b`: driver in organisation B
- `user_b`: attendee in organisation B

Create:

- `event_a`: active event in organisation A, assigned to `driver_a`
- `event_b`: active event in organisation B, assigned to `driver_b`
- `cancelled_event_a`: cancelled event in organisation A

Use each actor's authenticated JWT when testing client-accessible operations. Never use the service-role key for RLS regression cases except to set up fixtures.

## Expected Pass Cases

- `user_a` can subscribe to `event_a`.
- `user_a` can request pickup for `event_a` after subscribing.
- `driver_a` can select pickup requests for `event_a`.
- `driver_a` can update pickup status for `event_a`.
- `admin_a` can select events, members, subscriptions, pickup requests, and join requests in organisation A.
- `admin_a` can approve/reject pending join requests for organisation A.

## Expected Failure Cases

### Cross-Org Event Subscription

- As `user_a`, attempt to insert `event_subscriptions(event_id = event_b, user_id = user_a)`.
- Expected: insert is rejected by RLS.

### Cross-Org Pickup Request

- As `user_a`, attempt to insert `pickup_requests(event_id = event_b, user_id = user_a, pickup_location = POINT(...))`.
- Expected: insert is rejected by RLS.

### Pickup Without Subscription

- As a fresh `user_a` with no subscription to `event_a`, attempt to insert a pickup request for `event_a`.
- Expected: insert is rejected by RLS.

### Duplicate Pickup Request

- As `user_a`, request pickup for `event_a` twice.
- Expected: second insert fails because of `pickup_requests_event_user_unique`.

### Cancelled Event Pickup

- As `user_a`, attempt to subscribe/request pickup for `cancelled_event_a`.
- Expected: insert fails because event status is not active.

### Driver Updates Unassigned Event

- As `driver_b`, attempt to update a pickup request for `event_a`.
- Expected: update is rejected by RLS.

### User Self-Promotion

- As `user_a`, attempt to update own `profiles.role` to `admin` or `driver`.
- Expected: update is rejected by `profiles_update_own`.

### User Org Switch

- As `user_a`, attempt to update own `profiles.org_id` to organisation B.
- Expected: update is rejected by `profiles_update_own`.

### Admin Cross-Org Approval

- As `admin_b`, attempt to approve a join request for organisation A.
- Expected: `approve_join_request` raises an exception.

### Driver Approval Policy

- Set organisation A driver/staff access to approval.
- As a new driver, join organisation A via invite link.
- Expected: join returns a pending request, and the profile does not become a driver until `admin_a` approves.

### Attendee Allowlist Policy

- Set organisation A attendee access to allowlist.
- Add `user_a` email to the allowlist.
- As `user_a`, join via invite link.
- Expected: join succeeds and the allowlist row becomes claimed.
- As a non-allowlisted user, join via invite link.
- Expected: join is rejected.

### Direct Notification Function Call

- Call `send-notification` without `x-internal-token`.
- Expected: request returns unauthorized.

### Route Scheduling by Wrong Caller

- As `user_a` or `driver_b`, call `schedule-pickup` for `event_a`.
- Expected: request is rejected.

### Route Scheduling for Cancelled Event

- As assigned driver, call `schedule-pickup` for `cancelled_event_a`.
- Expected: request is rejected with non-active event error.

## Evidence to Capture

For each release candidate, record:

- Supabase project used
- schema commit/hash
- user IDs for actors
- pass/fail result for each case
- any unexpected error body
- fixes or follow-up tickets
