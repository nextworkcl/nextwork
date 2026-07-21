// Supabase Edge Function: envia una notificacion push real (llega aunque
// el navegador este cerrado) para una notificacion que YA existe en la
// tabla notifications. No crea notificaciones nuevas, solo las reenvia
// como push si el destinatario tiene una suscripcion activa.
//
// Se llama con {recipient_id, type, entity_id} -- los mismos datos que ya
// tiene el cliente justo despues de la accion que genero la notificacion
// (enviar un mensaje, aceptar una conexion, etc). La funcion busca esa
// fila exacta en notifications antes de mandar nada: si no existe, no
// hace nada. Asi no se puede abusar para spamear pushes a alguien -- solo
// se puede "reenviar" algo que los triggers de la base de datos ya
// validaron como una notificacion real.
//
// Deploy:
//   supabase functions deploy send-push
//
// Secrets necesarios:
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY (ver sw-push-setup.txt o el
//   mensaje donde Claude las genero)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY las inyecta Supabase automaticamente.

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

webpush.setVapidDetails(
  "mailto:team@nextwork.cl",
  Deno.env.get("VAPID_PUBLIC_KEY")!,
  Deno.env.get("VAPID_PRIVATE_KEY")!
);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BODY_BY_TYPE: Record<string, string> = {
  message: "te envió un mensaje",
  connection_request: "quiere conectar contigo",
  connection_accepted: "aceptó tu solicitud de conexión",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { recipient_id, type, entity_id } = await req.json();
    if (!recipient_id || !type) {
      return new Response(JSON.stringify({ error: "Faltan datos" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    let query = supabase
      .from("notifications")
      .select("*")
      .eq("recipient_id", recipient_id)
      .eq("type", type)
      .order("created_at", { ascending: false })
      .limit(1);
    if (entity_id) query = query.eq("entity_id", entity_id);

    const { data: notif } = await query.maybeSingle();
    if (!notif) {
      return new Response(JSON.stringify({ skipped: true }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { data: subs } = await supabase
      .from("push_subscriptions")
      .select("*")
      .eq("user_id", recipient_id);
    if (!subs || !subs.length) {
      return new Response(JSON.stringify({ sent: 0 }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    let actorName = "Alguien";
    if (notif.actor_id) {
      const { data: actor } = await supabase.from("profiles").select("name").eq("id", notif.actor_id).single();
      if (actor?.name) actorName = actor.name;
    }

    const title = "Nextwork";
    const body = `${actorName} ${BODY_BY_TYPE[type] || "interactuó contigo"}`;
    const url = type === "message" ? "/mensajes.html" : "/dashboard.html";
    const payload = JSON.stringify({ title, body, url });

    let sent = 0;
    for (const sub of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload
        );
        sent++;
      } catch (err: any) {
        if (err?.statusCode === 404 || err?.statusCode === 410) {
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        }
      }
    }

    return new Response(JSON.stringify({ sent }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
