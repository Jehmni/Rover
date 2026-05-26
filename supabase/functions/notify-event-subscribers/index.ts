// notify-event-subscribers — Supabase Edge Function
// Sends event update/cancellation notifications to subscribed attendees.
//
// Body: { event_id: number, notification_type: 'edited' | 'cancelled' }
// Deploy: supabase functions deploy notify-event-subscribers

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type EventNotificationType = 'edited' | 'cancelled'

const jsonHeaders = { 'Content-Type': 'application/json' }

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  })
}

function isEventNotificationType(value: unknown): value is EventNotificationType {
  return value === 'edited' || value === 'cancelled'
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

    const { event_id, notification_type } = await req.json()

    if (!Number.isInteger(event_id) || event_id <= 0) {
      return jsonResponse(
        { error: 'event_id must be a positive integer' },
        400,
      )
    }

    if (!isEventNotificationType(notification_type)) {
      return jsonResponse(
        { error: "notification_type must be either 'edited' or 'cancelled'" },
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

    const { data: event, error: eventErr } = await userClient
      .from('events')
      .select('id, name, org_id, admin_id')
      .eq('id', event_id)
      .maybeSingle()

    if (eventErr) {
      return jsonResponse({ error: eventErr.message }, 500)
    }
    if (!event) {
      return jsonResponse({ error: 'Event not found or access denied' }, 404)
    }
    if (event.admin_id !== user.id) {
      return jsonResponse({ error: 'Only the event admin can notify subscribers' }, 403)
    }

    const internalNotifyToken = Deno.env.get('INTERNAL_NOTIFY_TOKEN')
    if (!internalNotifyToken) {
      return jsonResponse({
        success: true,
        notified_count: 0,
        message: 'INTERNAL_NOTIFY_TOKEN is not configured',
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: subscriptions, error: subsErr } = await supabase
      .from('event_subscriptions')
      .select('user_id')
      .eq('event_id', event_id)

    if (subsErr) {
      return jsonResponse({ error: subsErr.message }, 500)
    }

    const userIds = (subscriptions ?? []).map((sub: any) => sub.user_id)
    if (userIds.length === 0) {
      return jsonResponse({ success: true, notified_count: 0 })
    }

    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, fcm_token')
      .in('id', userIds)

    const title = notification_type === 'cancelled'
      ? 'Event cancelled'
      : 'Event updated'
    const body = notification_type === 'cancelled'
      ? `${event.name ?? 'Your event'} has been cancelled.`
      : `${event.name ?? 'Your event'} details have changed.`

    let notifiedCount = 0

    await Promise.all((profiles ?? []).map(async (profile: any) => {
      if (!profile.fcm_token) return

      const { error } = await supabase.functions.invoke('send-notification', {
        headers: { 'x-internal-token': internalNotifyToken },
        body: {
          user_fcm_token: profile.fcm_token,
          title,
          body,
        },
      })

      if (!error) notifiedCount += 1
    }))

    return jsonResponse({
      success: true,
      notified_count: notifiedCount,
    })
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500)
  }
})
