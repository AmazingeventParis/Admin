import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { type, target_player_id, title, body } = await req.json()

    // Récupérer les credentials Firebase depuis les secrets
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT')
    if (!serviceAccountJson) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT not configured')
    }

    const serviceAccount = JSON.parse(serviceAccountJson)

    // Créer le client Supabase pour récupérer le FCM token du joueur
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Récupérer le FCM token du joueur cible
    const { data: player, error: playerError } = await supabase
      .from('players')
      .select('fcm_token, username')
      .eq('id', target_player_id)
      .single()

    if (playerError || !player?.fcm_token) {
      console.log('No FCM token found for player:', target_player_id)
      return new Response(
        JSON.stringify({ success: false, error: 'No FCM token' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Générer un access token pour FCM v1 API
    const accessToken = await getAccessToken(serviceAccount)

    // Envoyer la notification via FCM v1 API
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: player.fcm_token,
            notification: {
              title: title,
              body: body,
            },
            data: {
              type: type,
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channel_id: 'duel_notifications',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                  badge: 1,
                },
              },
            },
          },
        }),
      }
    )

    const fcmResult = await fcmResponse.json()
    console.log('FCM Response:', fcmResult)

    return new Response(
      JSON.stringify({ success: true, result: fcmResult }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error:', error)
    return new Response(
      JSON.stringify({ success: false, error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 500 }
    )
  }
})

// Génère un access token OAuth2 pour l'API FCM v1
async function getAccessToken(serviceAccount: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const expiry = now + 3600

  // Créer le JWT header
  const header = {
    alg: 'RS256',
    typ: 'JWT',
  }

  // Créer le JWT payload
  const payload = {
    iss: serviceAccount.client_email,
    sub: serviceAccount.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: expiry,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
  }

  // Encoder en base64url
  const encodeBase64Url = (obj: any) => {
    const json = JSON.stringify(obj)
    const base64 = btoa(json)
    return base64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
  }

  const headerEncoded = encodeBase64Url(header)
  const payloadEncoded = encodeBase64Url(payload)
  const unsignedToken = `${headerEncoded}.${payloadEncoded}`

  // Signer avec la clé privée RSA
  const privateKey = serviceAccount.private_key
  const signature = await signWithRSA(unsignedToken, privateKey)
  const jwt = `${unsignedToken}.${signature}`

  // Échanger le JWT contre un access token
  const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  })

  const tokenData = await tokenResponse.json()
  return tokenData.access_token
}

// Signe une chaîne avec RSA-SHA256
async function signWithRSA(data: string, privateKeyPem: string): Promise<string> {
  // Convertir PEM en format utilisable
  const pemHeader = '-----BEGIN PRIVATE KEY-----'
  const pemFooter = '-----END PRIVATE KEY-----'
  const pemContents = privateKeyPem
    .replace(pemHeader, '')
    .replace(pemFooter, '')
    .replace(/\s/g, '')

  const binaryKey = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  // Importer la clé
  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryKey,
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign']
  )

  // Signer
  const encoder = new TextEncoder()
  const dataBuffer = encoder.encode(data)
  const signatureBuffer = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', cryptoKey, dataBuffer)

  // Convertir en base64url
  const signatureArray = new Uint8Array(signatureBuffer)
  const signatureBase64 = btoa(String.fromCharCode(...signatureArray))
  return signatureBase64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '')
}
