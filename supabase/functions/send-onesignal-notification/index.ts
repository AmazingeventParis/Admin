import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const ONESIGNAL_APP_ID = "01e66a57-6563-4572-b396-ad338b648ddf"
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") || ""

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

interface NotificationRequest {
  target_player_id: string
  title: string
  body: string
  image_url?: string
  data?: Record<string, unknown>
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const { target_player_id, title, body, image_url, data }: NotificationRequest = await req.json()

    if (!target_player_id || !title || !body) {
      return new Response(
        JSON.stringify({ error: "Missing required fields" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Send notification via OneSignal REST API
    const onesignalResponse = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_external_user_ids: [target_player_id],
        headings: { en: title, fr: title },
        contents: { en: body, fr: body },
        big_picture: image_url,
        ios_attachments: image_url ? { photo: image_url } : undefined,
        data: data,
      }),
    })

    const result = await onesignalResponse.json()

    if (!onesignalResponse.ok) {
      console.error("OneSignal error:", result)
      return new Response(
        JSON.stringify({ error: "Failed to send notification", details: result }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    return new Response(
      JSON.stringify({ success: true, id: result.id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    console.error("Error:", error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})
