// send-notification — Supabase Edge Function
// Replaces the print() placeholder in rover.py with real FCM push notifications.
//
// Deploy:  supabase functions deploy send-notification
// Secrets: supabase secrets set FCM_SERVER_KEY=<your_fcm_server_key>
//
// Expected request body:
//   { user_fcm_token: string, title: string, body: string }

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const FCM_ENDPOINT = 'https://fcm.googleapis.com/fcm/send'

serve(async (req: Request) => {
  try {
    const { user_fcm_token, title, body } = await req.json()

    if (!user_fcm_token || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'user_fcm_token, title, and body are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const FCM_SERVER_KEY = Deno.env.get('FCM_SERVER_KEY')
    if (!FCM_SERVER_KEY) {
      return new Response(
        JSON.stringify({ error: 'FCM_SERVER_KEY secret is not configured' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      )
    }

    const fcmResponse = await fetch(FCM_ENDPOINT, {
      method: 'POST',
      headers: {
        Authorization: `key=${FCM_SERVER_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        to: user_fcm_token,
        notification: {
          title,
          body,
          sound: 'default',
        },
        // Data payload — available in background handlers
        data: {
          title,
          body,
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      }),
    })

    const result = await fcmResponse.json()

    if (!fcmResponse.ok) {
      return new Response(
        JSON.stringify({ error: 'FCM request failed', details: result }),
        { status: 502, headers: { 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ success: true, fcm_response: result }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    )
  }
})
