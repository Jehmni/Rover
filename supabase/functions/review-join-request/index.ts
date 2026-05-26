// review-join-request — Supabase Edge Function
// Lets an org admin approve/reject pending join requests and notifies the
// requester without exposing FCM tokens to the client.
//
// Body: { request_id: number, action: 'approve' | 'reject' }
// Deploy: supabase functions deploy review-join-request

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

type ReviewAction = 'approve' | 'reject'

const jsonHeaders = { 'Content-Type': 'application/json' }

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  })
}

function isReviewAction(value: unknown): value is ReviewAction {
  return value === 'approve' || value === 'reject'
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

    const { request_id, action } = await req.json()

    if (!Number.isInteger(request_id) || request_id <= 0) {
      return jsonResponse(
        { error: 'request_id must be a positive integer' },
        400,
      )
    }

    if (!isReviewAction(action)) {
      return jsonResponse(
        { error: "action must be either 'approve' or 'reject'" },
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

    const { data: requestRow, error: requestErr } = await userClient
      .from('org_join_requests')
      .select('id, org_id, user_id, status')
      .eq('id', request_id)
      .maybeSingle()

    if (requestErr) {
      return jsonResponse({ error: requestErr.message }, 500)
    }
    if (!requestRow) {
      return jsonResponse({ error: 'Join request not found or access denied' }, 404)
    }
    if (requestRow.status !== 'pending') {
      return jsonResponse({ error: 'Join request has already been reviewed' }, 409)
    }

    const rpcName = action === 'approve'
      ? 'approve_join_request'
      : 'reject_join_request'
    const { error: rpcErr } = await userClient.rpc(
      rpcName,
      { p_request_id: request_id },
    )

    if (rpcErr) {
      return jsonResponse({ error: rpcErr.message }, 403)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: org } = await supabase
      .from('organisations')
      .select('name')
      .eq('id', requestRow.org_id)
      .maybeSingle()

    const orgName = org?.name ?? 'the organisation'
    const notified = await notifyUser(
      supabase,
      requestRow.user_id,
      action === 'approve' ? 'Join request approved' : 'Join request rejected',
      action === 'approve'
        ? `You can now access ${orgName} on Rover.`
        : `Your request to join ${orgName} was rejected.`,
    )

    return jsonResponse({
      success: true,
      action,
      notified,
    })
  } catch (err) {
    return jsonResponse({ error: String(err) }, 500)
  }
})
