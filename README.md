# Rover
Event pickup management for multi-tenant organisations.

## Active Architecture
- Flutter mobile app: `front/roverfront`
- Supabase database + RLS + RPCs: `supabase/schema_restore.sql` (canonical bootstrap)
- Supabase edge functions (pickup scheduling, pickup status transitions, notifications): `supabase/functions`
- Firebase Cloud Messaging (HTTP v1 via service account secret)

## Core Features
- Email/password auth with role-based access (`user`, `driver`, `admin`)
- Organisation creation/join flow with invite tokens and QR/deep links
- Event management and driver assignment (admin)
- Event browse/subscribe/request pickup (user)
- Route ordering and ETA updates for assigned driver
- Push notifications for rider and driver status changes

## Quick Start (Flutter + Supabase)
1. Install Flutter and run `flutter doctor`.
2. Open `front/roverfront` and run `flutter pub get`.
3. Supply required Dart defines:
   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`
4. Run app:
   - `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
5. Apply database schema in Supabase SQL editor:
   - `supabase/schema_restore.sql` (canonical single-file bootstrap)
   - Migration files `schema_v3...schema_v7` are retained for historical/incremental patching.

## Environment and Secrets
- Client app uses Dart defines for Supabase URL/anon key.
- Edge functions require Supabase secrets (service-role key, Firebase service account JSON, and `INTERNAL_NOTIFY_TOKEN`).
- Deploy all production edge functions before release: `schedule-pickup`, `update-pickup-status`, `review-join-request`, `notify-event-subscribers`, and `send-notification`.
- See `.env.example` for expected values and naming.

## Notes
- This repository is Flutter + Supabase only.
