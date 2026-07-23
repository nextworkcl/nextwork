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
//   1. Si todavia no existe, crea UNA plantilla (Email Templates ->
//      Create New Template -> boton "</> Code Editor") y pega el HTML
//      de email-templates/notificacion.html. En el campo "Subject"
//      (fuera del editor de HTML) poner: {{subject}}
//      Esta MISMA plantilla la usa tambien send-notification-email -- el
//      plan gratuito de EmailJS solo permite 2 plantillas, asi que ambas
//      funciones comparten una sola en vez de gastar un slot cada una.
//   2. Copia el Template ID y ponlo como secret EMAILJS_TEMPLATE_ID
//      (si ya lo configuraste para send-notification-email, es el mismo
//      secret, no hace falta repetirlo)
//   3. En Account -> Security, activa "Allow requests from non-browser
//      applications" -- si no, EmailJS rechaza esta llamada porque no
//      viene de un navegador real.
//
// Secrets necesarios: EMAILJS_TEMPLATE_ID
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
        const contentHtml = `
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
            <tr>
              <td style="padding:36px 32px 8px;text-align:center;">
                <p style="margin:0 0 4px;font-size:16px;color:#0f0e0c;">Tu semana en <strong>Nextwork</strong></p>
                <p style="margin:0;font-size:13px;color:#7a7870;">Esto pasó en tu red los últimos 7 días</p>
              </td>
            </tr>
            <tr>
              <td style="padding:20px 32px 8px;">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                  <tr>
                    <td width="33%" align="center" style="padding:12px 6px;">
                      <div style="font-family:Georgia,'Times New Roman',serif;font-size:28px;color:#1a3a2a;font-weight:bold;">${newConnections}</div>
                      <div style="font-size:11px;color:#7a7870;margin-top:4px;">Conexiones nuevas</div>
                    </td>
                    <td width="33%" align="center" style="padding:12px 6px;">
                      <div style="font-family:Georgia,'Times New Roman',serif;font-size:28px;color:#1a3a2a;font-weight:bold;">${newMessages}</div>
                      <div style="font-size:11px;color:#7a7870;margin-top:4px;">Mensajes</div>
                    </td>
                    <td width="33%" align="center" style="padding:12px 6px;">
                      <div style="font-family:Georgia,'Times New Roman',serif;font-size:28px;color:#1a3a2a;font-weight:bold;">${profileViews}</div>
                      <div style="font-size:11px;color:#7a7870;margin-top:4px;">Visitas a tu perfil</div>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:16px 32px 32px;text-align:center;">
                <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:6px auto 0;">
                  <tr>
                    <td align="center" style="border-radius:22px;background-color:#1a3a2a;">
                      <a href="https://nextwork-55o.pages.dev/dashboard.html" style="display:inline-block;padding:12px 32px;font-size:14px;font-weight:500;color:#c8f0d8;text-decoration:none;border-radius:22px;font-family:'DM Sans',Helvetica,Arial,sans-serif;">Ir a mi Dashboard →</a>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>`;

        const res = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
          method: "POST",
          headers: { "Content-Type": "application/json", "origin": "https://nextwork-55o.pages.dev" },
          body: JSON.stringify({
            service_id: EMAILJS_SERVICE_ID,
            template_id: Deno.env.get("EMAILJS_TEMPLATE_ID"),
            user_id: EMAILJS_PUBLIC_KEY,
            template_params: {
              to_email: p.email,
              to_name: p.name || "",
              subject: "Tu semana en Nextwork",
              content_html: contentHtml,
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
