// schedule-pickup — Supabase Edge Function
// Computes an optimised pickup route and persists order + ETA to DB.
//
// Security fix (H-2):
//   A user-scoped Supabase client is created from the caller's JWT and used
//   to verify the caller is the assigned driver for the requested event
//   BEFORE the service-role client performs any writes.
//   Previously any authenticated user could trigger and corrupt route data.
//
// Deploy:  supabase functions deploy schedule-pickup
// Secrets: supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON=<json>

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const AVERAGE_SPEED_KMH = 30

// ─────────────────────────────────────────────────────────────
// Haversine great-circle distance (kilometres)
// ─────────────────────────────────────────────────────────────
function haversine(
  lat1: number, lon1: number,
  lat2: number, lon2: number,
): number {
  const R     = 6371
  const toRad = (d: number) => d * Math.PI / 180
  const dLat  = toRad(lat2 - lat1)
  const dLon  = toRad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// ─────────────────────────────────────────────────────────────
// Greedy nearest-neighbour ordering — O(n²)
// ─────────────────────────────────────────────────────────────
interface UserStop {
  id: string       // user_id
  pickup_id: number
  lat: number
  lon: number
}

interface OrderedStop extends UserStop {
  order: number
  eta_minutes: number
}

function nearestNeighborOrder(
  driverLat: number,
  driverLon: number,
  users: UserStop[],
): OrderedStop[] {
  const remaining = [...users]
  const ordered: OrderedStop[] = []
  let curLat = driverLat
  let curLon = driverLon
  let cumulativeKm = 0

  while (remaining.length > 0) {
    let nearestIdx  = 0
    let nearestDist = Infinity

    for (let i = 0; i < remaining.length; i++) {
      const d = haversine(curLat, curLon, remaining[i].lat, remaining[i].lon)
      if (d < nearestDist) { nearestDist = d; nearestIdx = i }
    }

    const nearest = remaining[nearestIdx]
    cumulativeKm += nearestDist
    const etaMinutes = Math.round((cumulativeKm / AVERAGE_SPEED_KMH) * 60)

    ordered.push({ ...nearest, order: ordered.length + 1, eta_minutes: etaMinutes })
    curLat = nearest.lat
    curLon = nearest.lon
    remaining.splice(nearestIdx, 1)
  }

  return ordered
}

// ─────────────────────────────────────────────────────────────
// Main handler
// Body: { event_id: number, driver_lat: number, driver_lon: number }
// ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  try {
    // ── 1. Parse and validate input ───────────────────────────
    const { event_id, driver_lat, driver_lon } = await req.json()

    if (!event_id || driver_lat == null || driver_lon == null) {
      return new Response(
        JSON.stringify({ error: 'event_id, driver_lat, and driver_lon are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      )
    }

    if (driver_lat < -90 || driver_lat > 90 || driver_lon < -180 || driver_lon > 180) {
      return new Response(
        JSON.stringify({ error: 'Invalid driver coordinates' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // ── 2. Verify caller is the assigned driver (H-2 fix) ─────
    // Build a user-scoped client from the caller's JWT so RLS
    // limits what they can see — the event query below will only
    // succeed if the caller's org_id matches and the event exists.
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Missing Authorization header' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )

    // Identify the caller
    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // Fetch the event — RLS ensures it's in the caller's org
    const { data: event, error: eventErr } = await userClient
      .from('events')
      .select('assigned_driver_id')
      .eq('id', event_id)
      .single()

    if (eventErr || !event) {
      return new Response(
        JSON.stringify({ error: 'Event not found or access denied' }),
        { status: 404, headers: { 'Content-Type': 'application/json' } },
      )
    }

    if (event.assigned_driver_id !== user.id) {
      return new Response(
        JSON.stringify({ error: 'You are not the assigned driver for this event' }),
        { status: 403, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // ── 3. Use service-role for privileged reads and writes ───
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Fetch all pending pickup requests for this event
    const { data: pickups, error: fetchError } = await supabase
      .from('pickup_requests')
      .select('id, user_id, pickup_location')
      .eq('event_id', event_id)
      .eq('status', 'pending')

    if (fetchError) {
      return new Response(
        JSON.stringify({ error: fetchError.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      )
    }

    if (!pickups || pickups.length === 0) {
      return new Response(
        JSON.stringify({ ordered: [], message: 'No pending pickup requests for this event' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // Parse PostGIS geography → { lat, lon }
    // Supabase returns geography as GeoJSON: { type: 'Point', coordinates: [lon, lat] }
    const users: UserStop[] = pickups.map((p: any) => ({
      id:        p.user_id,
      pickup_id: p.id,
      lon:       p.pickup_location.coordinates[0],  // GeoJSON: lon first
      lat:       p.pickup_location.coordinates[1],  // then lat
    }))

    // ── 4. Compute optimal order ──────────────────────────────
    const ordered = nearestNeighborOrder(driver_lat, driver_lon, users)

    // ── 5. Persist pickup_order + eta_minutes to each row ─────
    await Promise.all(
      ordered.map((stop) =>
        supabase
          .from('pickup_requests')
          .update({
            pickup_order: stop.order,
            eta_minutes:  stop.eta_minutes,
            status:       'pending',  // keep pending; driver marks en_route/completed manually
          })
          .eq('id', stop.pickup_id)
      ),
    )

    // ── 6. Notify the first user in the sequence via FCM ─────
    const firstStop = ordered[0]
    const { data: profile } = await supabase
      .from('profiles')
      .select('fcm_token, full_name')
      .eq('id', firstStop.id)
      .single()

    if (profile?.fcm_token) {
      // Fire-and-forget — notification failure must not fail the route call
      supabase.functions.invoke('send-notification', {
        body: {
          user_fcm_token: profile.fcm_token,
          title: 'Your driver is on the way',
          body:  `You are stop #1. ETA: ${firstStop.eta_minutes} minutes.`,
        },
      }).catch(() => { /* non-fatal */ })
    }

    return new Response(
      JSON.stringify({ ordered }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
