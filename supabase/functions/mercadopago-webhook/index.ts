// Supabase Edge Function: recibe las notificaciones de MercadoPago y
// activa/desactiva el plan Pro segun el estado real de la suscripcion.
// MercadoPago manda notificaciones "livianas" (solo tipo + id), asi que
// esta funcion vuelve a consultar la API para obtener el estado real
// antes de decidir nada.
//
// Deploy (OJO con --no-verify-jwt: MercadoPago no manda un JWT de
// Supabase, no hay forma de que pase la verificacion por defecto):
//   supabase functions deploy mercadopago-webhook --no-verify-jwt
//
// Configura la URL de notificaciones en MercadoPago -> Tus integraciones
// -> tu aplicacion -> Webhooks:
//   URL: https://<tu-proyecto>.supabase.co/functions/v1/mercadopago-webhook
//   Eventos: "Suscripciones" (subscription_preapproval)
//
// Secrets necesarios: MP_ACCESS_TOKEN

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

serve(async (req) => {
  try {
    const url = new URL(req.url);
    let type = url.searchParams.get("type") || url.searchParams.get("topic");
    let id = url.searchParams.get("id") || url.searchParams.get("data.id");

    if (!type || !id) {
      try {
        const body = await req.json();
        type = type || body.type;
        id = id || body.data?.id;
      } catch (_e) {
        // body vacio o no-JSON: seguimos con lo que haya llegado en la URL
      }
    }

    // Solo nos interesan los eventos de la suscripcion en si (no pagos
    // individuales sueltos, que MercadoPago tambien puede notificar)
    if (type !== "subscription_preapproval" && type !== "preapproval") {
      return new Response("ignored", { status: 200 });
    }
    if (!id) {
      return new Response("missing id", { status: 200 });
    }

    const mpRes = await fetch(`https://api.mercadopago.com/preapproval/${id}`, {
      headers: { "Authorization": `Bearer ${Deno.env.get("MP_ACCESS_TOKEN")}` },
    });
    const preapproval = await mpRes.json();
    if (!mpRes.ok || !preapproval.external_reference) {
      return new Response("preapproval not found", { status: 200 });
    }

    const isActive = preapproval.status === "authorized";
    const nextPayment = preapproval.next_payment_date
      ? new Date(preapproval.next_payment_date).toISOString()
      : null;

    await supabase.from("profiles").update({
      pro_active: isActive,
      pro_current_period_end: nextPayment,
      mercadopago_subscription_id: preapproval.id,
    }).eq("id", preapproval.external_reference);

    return new Response("ok", { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500 });
  }
});
