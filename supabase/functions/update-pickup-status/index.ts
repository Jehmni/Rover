// update-pickup-status — Supabase Edge Function
// Lets the assigned driver move a pickup through the route lifecycle and
// sends attendee notifications without exposing FCM tokens to the client.
//
// Body: { pickup_request_id: number, status: 'en_route' | 'completed' }
// Deploy: supabase functions deploy update-pickup-status

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type PickupStatus = 'en_route' | 'completed'

interface PickupRequest {
  id: number
  event_id: number
  user_id: string
  status: string
  pickup_order: number | null
  eta_minutes: number | null
}

const jsonHeaders = { 'Content-Type': 'application/json' }

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  })
}

function isPickupStatus(value: unknown): value is PickupStatus {
  return value === 'en_route' || value === 'completed'
}

function canTransition(currentStatus: string, nextStatus: PickupStatus): boolean {
  if (currentStatus === nextStatus) return true
  if (nextStatus === 'en_route') return currentStatus === 'pending'
  if (nextStatus === 'completed') {
    return currentStatus === 'pending' || currentStatus === 'en_route'
  }
  return false
}

function etaText(etaMinutes: number | null): string {
  return etaMinutes == null ? '' : ` ETA: ${etaMinutes} minutes.`
}

async function notifyUser(
  supabase: ReturnType<typeof createClient>,
  userId: string,
  title: string,
  body: string,
): Promise<boolean> {
  const internalNotifyToken = Deno.env.get('INTERNAL_NOTIFY_TOKEN')
  if (!internalNotifyToken) return false

  const { data: profile } = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', userId)
    .maybeSingle()

  if (!profile?.fcm_token) return false

  const { error } = await supabase.functions.invoke('send-notification', {
    headers: { 'x-internal-token': internalNotifyToken },
    body: {
      user_fcm_token: profile.fcm_token,
      title,
      body,
    },
  })

  return !error
}

serve(async (req: Request) => {
  try {
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'Method not allowed' }, 405)
    }

    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return jsonResponse({ error: 'Missing Authorization header' }, 401)
    }

    const { pickup_request_id, status } = await req.json()

    if (!Number.isInteger(pickup_request_id) || pickup_request_id <= 0) {
      return jsonResponse(
        { error: 'pickup_request_id must be a positive integer' },
        400,
      )
    }

    if (!isPickupStatus(status)) {
      return jsonResponse(
        { error: "status must be either 'en_route' or 'completed'" },
        400,
      )
    }

    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: { user }, error: authErr } = await userClient.auth.getUser()
    if (authErr || !user) {
      return jsonResponse({ error: 'Unauthorized' }, 401)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: pickup, error: pickupErr } = await supabase
      .from('pickup_requests')
      .select('id, event_id, user_id, status, pickup_order, eta_minutes')
      .eq('id', pickup_request_id)
      .maybeSingle()

    if (pickupErr) {
      return jsonResponse({ error: pickupErr.message }, 500)
    }
    if (!pickup) {
      return jsonResponse({ error: 'Pickup request not found' }, 404)
    }

    const pickupRequest = pickup as PickupRequest

    const { data: event, error: eventErr } = await supabase
      .from('events')
      .select('id, name, assigned_driver_id, status')
      .eq('id', pickupRequest.event_id)
      .maybeSingle()

    if (eventErr) {
      return jsonResponse({ error: eventErr.message }, 500)
    }
    if (!event) {
      return jsonResponse({ error: 'Event not found' }, 404)
    }

    if (event.assigned_driver_id !== user.id) {
      return jsonResponse(
        { error: 'You are not the assigned driver for this event' },
        403,
      )
    }

    if (event.status !== 'active') {
      return jsonResponse(
        { error: 'Cannot update pickups for a non-active event' },
        409,
      )
    }

    if (pickupRequest.status === status) {
      return jsonResponse({
        success: true,
        status,
        unchanged: true,
        notified_current: false,
        notified_next: false,
      })
    }

    if (!canTransition(pickupRequest.status, status)) {
      return jsonResponse(
        { error: `Cannot transition pickup from ${pickupRequest.status} to ${status}` },
        409,
      )
    }

    const { error: updateErr } = await supabase
      .from('pickup_requests')
      .update({ status })
      .eq('id', pickupRequest.id)

    if (updateErr) {
      return jsonResponse({ error: updateErr.message }, 500)
    }

    let notifiedCurrent = false
    let notifiedNext = false

    if (status === 'en_route') {
      const stopText = pickupRequest.pickup_order == null
        ? ''
        : ` You are stop #${pickupRequest.pickup_order}.`
      notifiedCurrent = await notifyUser(
        supabase,
        pickupRequest.user_id,
        'Your driver is on the way',
        `${event.name ?? 'Your event'} pickup is now en route.${stopText}${etaText(pickupRequest.eta_minutes)}`,
      )
    }

    if (status === 'completed') {
      let nextQuery = supabase
        .from('pickup_requests')
        .select('id, user_id, pickup_order, eta_minutes')
        .eq('event_id', pickupRequest.event_id)
        .eq('status', 'pending')
        .not('pickup_order', 'is', null)

      if (pickupRequest.pickup_order != null) {
        nextQuery = nextQuery.gt('pickup_order', pickupRequest.pickup_order)
      }

      const { data: nextStops } = await nextQuery
        .order('pickup_order', { ascending: true })
        .limit(1)
      const nextStop = nextStops?.[0]

      if (nextStop) {
        notifiedNext = await notifyUser(
          supabase,
          nextStop.user_id,
          'You are next for pickup',
          `${event.name ?? 'Your event'} pickup is coming up. You are stop #${nextStop.pickup_order}.${etaText(nextStop.eta_minutes)}`,
        )
      }
    }

    return jsonResponse({
      success: true,
      status,
      notified_current: notifiedCurrent,
      notified_next: notifiedNext,
    })
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500)
  }
})
