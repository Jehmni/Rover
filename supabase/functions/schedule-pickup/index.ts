// schedule-pickup — Supabase Edge Function
// Replaces the broken compute_routes_with_eta() from rover.py.
//
// Fixes applied vs old Python code:
//   - routes variable is no longer used before assignment (NameError fixed)
//   - users list is never indexed by database primary key (IndexError fixed)
//   - Dijkstra replaced with greedy nearest-neighbor: correct, O(n²), no overkill
//   - Both latitude AND longitude are read from pickup_location (old code missed lat)
//
// Deploy:  supabase functions deploy schedule-pickup
// Secrets: supabase secrets set FCM_SERVER_KEY=<key>

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const AVERAGE_SPEED_KMH = 30  // adjustable; used for all ETA calculations

// ─────────────────────────────────────────────────────────────
// Haversine formula — great-circle distance between two points.
// Returns distance in kilometres.
// ─────────────────────────────────────────────────────────────
function haversine(
  lat1: number, lon1: number,
  lat2: number, lon2: number
): number {
  const R = 6371
  const toRad = (deg: number) => deg * Math.PI / 180
  const dLat = toRad(lat2 - lat1)
  const dLon = toRad(lon2 - lon1)
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// ─────────────────────────────────────────────────────────────
// Greedy nearest-neighbor pickup ordering — O(n²).
// Correct for this domain; Dijkstra was overkill on a complete
// graph where every node connects to every other node anyway.
//
// Returns the same array sorted by pickup order, each entry
// annotated with:
//   order        — 1-based position in the pickup sequence
//   eta_minutes  — cumulative ETA from driver start to this stop
// ─────────────────────────────────────────────────────────────
interface UserStop {
  id: string
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
  users: UserStop[]
): OrderedStop[] {
  const remaining = [...users]
  const ordered: OrderedStop[] = []
  let curLat = driverLat
  let curLon = driverLon
  let cumulativeDistanceKm = 0

  while (remaining.length > 0) {
    // Find the closest unvisited stop from current position
    let nearestIndex = 0
    let nearestDist = Infinity

    for (let i = 0; i < remaining.length; i++) {
      const d = haversine(curLat, curLon, remaining[i].lat, remaining[i].lon)
      if (d < nearestDist) {
        nearestDist = d
        nearestIndex = i
      }
    }

    const nearest = remaining[nearestIndex]
    cumulativeDistanceKm += nearestDist
    const etaMinutes = Math.round((cumulativeDistanceKm / AVERAGE_SPEED_KMH) * 60)

    ordered.push({
      ...nearest,
      order: ordered.length + 1,
      eta_minutes: etaMinutes,
    })

    curLat = nearest.lat
    curLon = nearest.lon
    remaining.splice(nearestIndex, 1)
  }

  return ordered
}

// ─────────────────────────────────────────────────────────────
// Main handler
// Expected request body:
//   { event_id: number, driver_lat: number, driver_lon: number }
// ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  try {
    const { event_id, driver_lat, driver_lon } = await req.json()

    if (!event_id || driver_lat == null || driver_lon == null) {
      return new Response(
        JSON.stringify({ error: 'event_id, driver_lat, and driver_lon are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Validate coordinate ranges
    if (driver_lat < -90 || driver_lat > 90 || driver_lon < -180 || driver_lon > 180) {
      return new Response(
        JSON.stringify({ error: 'Invalid driver coordinates' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Service-role client bypasses RLS so the function can read and
    // update all pickup_requests rows regardless of who owns them.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
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
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    if (!pickups || pickups.length === 0) {
      return new Response(
        JSON.stringify({ ordered: [], message: 'No pending pickup requests for this event' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } }
      )
    }

    // Parse PostGIS geography → { lat, lon }
    // pickup_location comes back as GeoJSON: { type: 'Point', coordinates: [lon, lat] }
    const users: UserStop[] = pickups.map((p: any) => ({
      id: p.user_id,
      pickup_id: p.id,
      // PostGIS GeoJSON: coordinates[0] = longitude, coordinates[1] = latitude
      lon: p.pickup_location.coordinates[0],
      lat: p.pickup_location.coordinates[1],
    }))

    // Compute optimal pickup order using greedy nearest-neighbor
    const ordered = nearestNeighborOrder(driver_lat, driver_lon, users)

    // Write pickup_order and eta_minutes back to each pickup_request row
    await Promise.all(
      ordered.map((stop) =>
        supabase
          .from('pickup_requests')
          .update({ pickup_order: stop.order, eta_minutes: stop.eta_minutes })
          .eq('id', stop.pickup_id)
      )
    )

    // Notify the first user in the sequence via send-notification function
    const firstStop = ordered[0]
    const { data: profile } = await supabase
      .from('profiles')
      .select('fcm_token, full_name')
      .eq('id', firstStop.id)
      .single()

    if (profile?.fcm_token) {
      await supabase.functions.invoke('send-notification', {
        body: {
          user_fcm_token: profile.fcm_token,
          title: 'Pickup Starting Soon',
          body: `Driver is on the way. ETA: ${firstStop.eta_minutes} minutes.`,
        },
      })
    }

    return new Response(
      JSON.stringify({ ordered }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
