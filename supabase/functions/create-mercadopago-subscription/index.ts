// Supabase Edge Function: crea una suscripcion (preapproval) de MercadoPago
// para el plan "Nextwork Pro" y devuelve la URL de pago (init_point) a la
// que el frontend (pro.html) redirige al usuario.
//
// Deploy:
//   supabase functions deploy create-mercadopago-subscription
//
// Secrets necesarios (supabase secrets set NOMBRE=valor):
//   MP_ACCESS_TOKEN   -> Access Token de tu cuenta de MercadoPago
//                        (Developers -> Tus integraciones -> Credenciales).
//                        Usa las credenciales de PRUEBA primero (empiezan
//                        con TEST-). Para probar de verdad en sandbox
//                        necesitas ademas crear "usuarios de prueba" desde
//                        el panel de MercadoPago (vendedor y comprador),
//                        una cuenta real de Chile no sirve como payer_email
//                        mientras uses credenciales TEST-.
//   SITE_URL          -> https://nextwork-55o.pages.dev
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las inyecta Supabase automaticamente.

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const PRO_PRICE_CLP = 9990;

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No autorizado" }), {
        status: 401,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const token = authHeader.replace("Bearer ", "");
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Sesión inválida" }), {
        status: 401,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { data: profile } = await supabase
      .from("profiles")
      .select("email")
      .eq("id", user.id)
      .single();

    const siteUrl = Deno.env.get("SITE_URL") || "https://nextwork-55o.pages.dev";

    const mpRes = await fetch("https://api.mercadopago.com/preapproval", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("MP_ACCESS_TOKEN")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        reason: "Nextwork Pro - Suscripción mensual",
        external_reference: user.id,
        payer_email: profile?.email || user.email,
        back_url: `${siteUrl}/dashboard.html?pro=success`,
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          transaction_amount: PRO_PRICE_CLP,
          currency_id: "CLP",
        },
        status: "pending",
      }),
    });

    const mpData = await mpRes.json();
    if (!mpRes.ok) {
      return new Response(JSON.stringify({ error: mpData.message || "MercadoPago rechazó la solicitud" }), {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ url: mpData.init_point }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
