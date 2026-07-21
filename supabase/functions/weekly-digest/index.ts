// Supabase Edge Function: resumen semanal por correo (conexiones nuevas,
// mensajes recibidos, visitas al perfil de los ultimos 7 dias). Se salta
// a cualquiera que no tuvo actividad -- nunca manda un correo vacio.
//
// Deploy:
//   supabase functions deploy weekly-digest
//
// Programarla para que corra sola una vez por semana:
//   Supabase Dashboard -> Edge Functions -> weekly-digest -> pestaña "Cron"
//   -> crear un trigger, ej. "0 13 * * 1" (todos los lunes 13:00 UTC).
//   No requiere pg_cron ni pg_net, Supabase lo maneja por su cuenta.
//
// IMPORTANTE -- antes de que esto funcione, en EmailJS (emailjs.com):
//   1. Crea una plantilla nueva (Email Templates -> Create New Template)
//      con estas variables exactas: {{to_email}}, {{to_name}},
//      {{new_connections}}, {{new_messages}}, {{profile_views}}
//   2. Copia el Template ID y ponlo como secret EMAILJS_DIGEST_TEMPLATE_ID
//   3. En Account -> Security, activa "Allow requests from non-browser
//      applications" -- si no, EmailJS rechaza esta llamada porque no
//      viene de un navegador real.
//
// Secrets necesarios: EMAILJS_DIGEST_TEMPLATE_ID
// (el service_id y la public key de EmailJS ya son publicos en el sitio,
// se reutilizan los mismos que usa crear-perfil.html)

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const EMAILJS_SERVICE_ID = "service_kr7yft1";
const EMAILJS_PUBLIC_KEY = "qCCiB5C-ktvGFIFyt";

serve(async (_req) => {
  try {
    const weekAgo = new Date(Date.now() - 7 * 24 * 3600 * 1000).toISOString();

    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, name, email, email_digest_opt_out")
      .eq("email_digest_opt_out", false);
    if (!profiles || !profiles.length) {
      return new Response(JSON.stringify({ sent: 0 }), { headers: { "Content-Type": "application/json" } });
    }

    const [{ data: conns }, { data: msgs }, { data: views }] = await Promise.all([
      supabase.from("connections").select("from_id,to_id").eq("status", "accepted").gte("responded_at", weekAgo),
      supabase.from("messages").select("recipient_id").gte("created_at", weekAgo),
      supabase.from("profile_views").select("profile_id").gte("created_at", weekAgo),
    ]);

    const connCountByUser: Record<string, number> = {};
    (conns || []).forEach((c: any) => {
      connCountByUser[c.from_id] = (connCountByUser[c.from_id] || 0) + 1;
      connCountByUser[c.to_id] = (connCountByUser[c.to_id] || 0) + 1;
    });

    const msgCountByUser: Record<string, number> = {};
    (msgs || []).forEach((m: any) => {
      msgCountByUser[m.recipient_id] = (msgCountByUser[m.recipient_id] || 0) + 1;
    });

    const viewCountByUser: Record<string, number> = {};
    (views || []).forEach((v: any) => {
      viewCountByUser[v.profile_id] = (viewCountByUser[v.profile_id] || 0) + 1;
    });

    let sent = 0;
    for (const p of profiles) {
      const newConnections = connCountByUser[p.id] || 0;
      const newMessages = msgCountByUser[p.id] || 0;
      const profileViews = viewCountByUser[p.id] || 0;
      if (newConnections === 0 && newMessages === 0 && profileViews === 0) continue;
      if (!p.email) continue;

      try {
        const res = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
          method: "POST",
          headers: { "Content-Type": "application/json", "origin": "https://nextwork-55o.pages.dev" },
          body: JSON.stringify({
            service_id: EMAILJS_SERVICE_ID,
            template_id: Deno.env.get("EMAILJS_DIGEST_TEMPLATE_ID"),
            user_id: EMAILJS_PUBLIC_KEY,
            template_params: {
              to_email: p.email,
              to_name: p.name || "",
              new_connections: String(newConnections),
              new_messages: String(newMessages),
              profile_views: String(profileViews),
            },
          }),
        });
        if (res.ok) sent++;
      } catch (_e) {
        // seguimos con el resto aunque uno falle
      }
    }

    return new Response(JSON.stringify({ sent, total_candidates: profiles.length }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
