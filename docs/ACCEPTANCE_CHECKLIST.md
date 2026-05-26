# Rover End-to-End Acceptance Checklist

Use this checklist before declaring a release candidate complete. Run it against a fresh Supabase project bootstrapped from `supabase/schema_restore.sql` and real Android/iOS devices where possible.

## Setup

- Apply `supabase/schema_restore.sql` to a fresh project.
- Deploy `schedule-pickup`, `update-pickup-status`, `review-join-request`, `notify-event-subscribers`, and `send-notification`.
- Set required Supabase secrets:
  - `SUPABASE_SERVICE_ROLE_KEY`
  - `GOOGLE_SERVICE_ACCOUNT_JSON`
  - `INTERNAL_NOTIFY_TOKEN`
- Run the Flutter app with `SUPABASE_URL` and `SUPABASE_ANON_KEY`.
- Confirm Firebase config is present for the target platform.

## Core Happy Path

1. Register an admin account.
2. Create an organisation.
3. Create an active event.
4. Share the org invite link or QR code.
5. Register a driver account and join via QR/deep link.
6. Register an attendee account and join via QR/deep link.
7. Confirm the driver appears in the admin driver assignment list.
8. Assign the driver to the event.
9. As attendee, subscribe to the event.
10. As attendee, request pickup and allow location permission.
11. As driver, start the route.
12. Confirm pickup order and ETA are saved.
13. As attendee, confirm pickup status/ETA appears.
14. As driver, mark attendee en route.
15. As attendee, confirm status updates.
16. As driver, mark attendee picked up/completed.
17. As attendee, confirm active ETA clears after completion.

## Cancellation and Recovery

- As attendee, request a pickup and then cancel it before completion.
- Confirm the driver pickup list updates after cancellation.
- Confirm completed pickups cannot be cancelled.
- As admin, cancel an event.
- Confirm attendees no longer see the cancelled event as active.
- Confirm drivers cannot schedule a route for the cancelled event.

## Invite and Join Controls

- Reset the admin invite link.
- Confirm old QR/share link fails.
- Confirm new QR/share link works.
- Search for the organisation from a no-link account.
- Send a join request.
- Approve the join request from the admin Share tab.
- Repeat with another user and reject the request.
- Confirm approved user joins and rejected user does not.

## Conference Allowlist

- Create a conference organisation.
- In the Share tab, set attendee access to allowlist mode.
- Add an allowlist email in-app.
- Confirm an allowlisted email can join.
- Confirm a non-allowlisted email is rejected.
- Confirm a claimed allowlist slot cannot be reused unexpectedly.
- Remove an allowlist email and confirm it can no longer be used.

## Notifications

- Confirm FCM token is saved after join without logout/login.
- Confirm route scheduling notification sends to the intended attendee.
- Confirm en-route notification sends when the driver marks a pickup en route.
- Confirm the next pending attendee is notified when the previous pickup is completed.
- Confirm join request approval and rejection notifications send to the requester.
- Confirm event edit and cancellation notifications send to subscribed users.
- Confirm missing FCM tokens do not fail route scheduling.
- Confirm missing FCM tokens do not fail pickup status updates.
- Confirm missing FCM tokens do not fail join request approval/rejection.
- Confirm missing FCM tokens do not fail event edit/cancellation updates.
- Confirm notification failures do not roll back successful route/status updates.

## Realtime

- Confirm admin pending join request list updates without app restart.
- Confirm driver pickup list updates when attendee requests/cancels pickup.
- Confirm attendee status updates when driver marks en route/completed.
- Reopen each screen and confirm state is still correct without relying on websocket history.

## Release Readiness

- Run `flutter analyze`.
- Run `flutter test`.
- Build Android release.
- Build iOS archive.
- Verify camera, notification, location, and deep-link permissions on device.
- Update `README.md`, `ROVER_USER_GUIDE.md`, and `WHITEPAPER.md` if observed behavior differs from docs.
