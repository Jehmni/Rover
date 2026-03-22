// send-notification — Supabase Edge Function
// Sends FCM push notifications via the Firebase Cloud Messaging HTTP v1 API.
//
// BREAKING CHANGE from previous version:
//   The FCM Legacy HTTP API (fcm.googleapis.com/fcm/send) was shut down
//   by Google in June 2024. This function now uses the FCM HTTP v1 API
//   with OAuth 2.0 service account credentials.
//
// Setup:
//   1. In Firebase Console → Project Settings → Service Accounts,
//      generate a new private key (downloads a JSON file).
//   2. Store the entire JSON content as a Supabase secret:
//        supabase secrets set GOOGLE_SERVICE_ACCOUNT_JSON='<paste json here>'
//   3. Deploy: supabase functions deploy send-notification
//
// Expected request body:
//   { user_fcm_token: string, title: string, body: string }

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

// ─────────────────────────────────────────────────────────────
// PEM private key → ArrayBuffer (Web Crypto API requires this format)
// ─────────────────────────────────────────────────────────────
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const binary = atob(base64)
  const buffer = new ArrayBuffer(binary.length)
  const view = new Uint8Array(buffer)
  for (let i = 0; i < binary.length; i++) {
    view[i] = binary.charCodeAt(i)
  }
  return buffer
}

// ─────────────────────────────────────────────────────────────
// Base64url encode (RFC 4648 §5) — needed for JWT construction
// ─────────────────────────────────────────────────────────────
function base64url(input: string | ArrayBuffer): string {
  let bytes: Uint8Array
  if (typeof input === 'string') {
    bytes = new TextEncoder().encode(input)
  } else {
    bytes = new Uint8Array(input)
  }
  const binary = Array.from(bytes).map(b => String.fromCharCode(b)).join('')
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '')
}

// ─────────────────────────────────────────────────────────────
// Build and sign a Google OAuth2 JWT using RS256.
// Exchanges the JWT for a short-lived access token which is then
// used to authenticate the FCM v1 API call.
// ─────────────────────────────────────────────────────────────
interface ServiceAccount {
  client_email: string
  private_key: string
  project_id: string
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  const header = { alg: 'RS256', typ: 'JWT' }
  const payload = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }

  const encodedHeader  = base64url(JSON.stringify(header))
  const encodedPayload = base64url(JSON.stringify(payload))
  const signingInput   = `${encodedHeader}.${encodedPayload}`

  // Import the RSA private key from PEM
  const privateKeyBuffer = pemToArrayBuffer(sa.private_key)
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    privateKeyBuffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  // Sign the JWT
  const signatureBuffer = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(signingInput),
  )
  const encodedSignature = base64url(signatureBuffer)
  const jwt = `${signingInput}.${encodedSignature}`

  // Exchange the signed JWT for a Google OAuth2 access token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })

  if (!tokenRes.ok) {
    const err = await tokenRes.text()
    throw new Error(`OAuth2 token exchange failed: ${err}`)
  }

  const tokenData = await tokenRes.json()
  return tokenData.access_token as string
}

// ─────────────────────────────────────────────────────────────
// Main handler
// ─────────────────────────────────────────────────────────────
serve(async (req: Request) => {
  try {
    const { user_fcm_token, title, body } = await req.json()

    if (!user_fcm_token || !title || !body) {
      return new Response(
        JSON.stringify({ error: 'user_fcm_token, title, and body are required' }),
        { status: 400, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const saJson = Deno.env.get('GOOGLE_SERVICE_ACCOUNT_JSON')
    if (!saJson) {
      return new Response(
        JSON.stringify({ error: 'GOOGLE_SERVICE_ACCOUNT_JSON secret is not configured' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      )
    }

    const sa: ServiceAccount = JSON.parse(saJson)

    // Obtain a short-lived access token via service account JWT
    const accessToken = await getGoogleAccessToken(sa)

    // Send the notification via FCM HTTP v1 API
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`

    const fcmRes = await fetch(fcmUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: user_fcm_token,
          notification: { title, body },
          android: {
            notification: { sound: 'default', channel_id: 'rover_pickups' },
          },
          apns: {
            payload: { aps: { sound: 'default', badge: 1 } },
          },
        },
      }),
    })

    const result = await fcmRes.json()

    if (!fcmRes.ok) {
      return new Response(
        JSON.stringify({ error: 'FCM request failed', details: result }),
        { status: 502, headers: { 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ success: true, message_id: result.name }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    )
  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } },
    )
  }
})
