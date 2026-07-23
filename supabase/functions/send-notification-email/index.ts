// Supabase Edge Function: notificacion instantanea por correo (like,
// comentario, solicitud de conexion, conexion aceptada) para una
// notificacion que YA existe en la tabla notifications. Mismo patron de
// seguridad que send-push: solo "reenvia" como correo algo que los
// triggers de la base de datos ya crearon y validaron -- no genera
// notificaciones nuevas ni permite spamear a nadie con datos inventados.
//
// Deploy:
//   supabase functions deploy send-notification-email
//
// IMPORTANTE -- antes de que esto funcione, en EmailJS (emailjs.com):
//   1. Si todavia no existe, crea UNA plantilla (Email Templates ->
//      Create New Template -> boton "</> Code Editor") y pega el HTML
//      de email-templates/notificacion.html. En el campo "Subject"
//      (fuera del editor de HTML) poner: {{subject}}
//      Esta MISMA plantilla la usa tambien weekly-digest -- el plan
//      gratuito de EmailJS solo permite 2 plantillas, asi que ambas
//      funciones comparten una sola en vez de gastar un slot cada una.
//   2. Copia el Template ID y ponlo como secret EMAILJS_TEMPLATE_ID
//      (si ya lo configuraste para weekly-digest, es el mismo secret,
//      no hace falta repetirlo)
//   3. Confirma que "Allow requests from non-browser applications" este
//      activado en Account -> Security
//
// Secrets necesarios: EMAILJS_TEMPLATE_ID
// (service_id y public key de EmailJS se reutilizan, ya son publicos --
// los mismos que usa weekly-digest)

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const EMAILJS_SERVICE_ID = "service_kr7yft1";
const EMAILJS_PUBLIC_KEY = "qCCiB5C-ktvGFIFyt";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ACTION_TEXT: Record<string, string> = {
  post_like: "le dio like a tu publicación",
  post_comment: "comentó tu publicación",
  connection_request: "quiere conectar contigo en Nextwork",
  connection_accepted: "aceptó tu solicitud de conexión",
};

const CTA_LABEL: Record<string, string> = {
  post_like: "Ver publicación",
  post_comment: "Ver comentario",
  connection_request: "Ver solicitud",
  connection_accepted: "Ver perfil",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const { recipient_id, type, entity_id } = await req.json();
    if (!recipient_id || !type || !ACTION_TEXT[type]) {
      return new Response(JSON.stringify({ error: "Tipo no soportado" }), {
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

    const { data: recipient } = await supabase
      .from("profiles")
      .select("name, email")
      .eq("id", recipient_id)
      .single();
    if (!recipient?.email) {
      return new Response(JSON.stringify({ skipped: true, reason: "sin email" }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    let actorName = "Alguien";
    let actorColor = "#2d6b4a";
    let actorRole = "";
    if (notif.actor_id) {
      const { data: actor } = await supabase
        .from("profiles")
        .select("name,color,role")
        .eq("id", notif.actor_id)
        .single();
      if (actor?.name) actorName = actor.name;
      if (actor?.color) actorColor = actor.color;
      if (actor?.role) actorRole = actor.role;
    }
    const actorInitial = actorName.trim().charAt(0).toUpperCase() || "N";

    let previewText = "";
    let actionUrl = "https://nextwork-55o.pages.dev/dashboard.html";
    if (type === "post_like" || type === "post_comment") {
      actionUrl = "https://nextwork-55o.pages.dev/publicaciones.html";
      if (notif.entity_id) {
        const { data: post } = await supabase.from("posts").select("body").eq("id", notif.entity_id).single();
        if (post?.body) previewText = post.body.length > 140 ? post.body.slice(0, 140) + "…" : post.body;
      }
      if (!previewText) previewText = "Entra a Nextwork para ver tu publicación.";
    } else if (type === "connection_request") {
      actionUrl = "https://nextwork-55o.pages.dev/dashboard.html#requests-wrap";
      previewText = actorRole
        ? `${actorName} · ${actorRole} quiere sumarse a tu red en Nextwork.`
        : `${actorName} quiere sumarse a tu red en Nextwork.`;
    } else if (type === "connection_accepted") {
      actionUrl = notif.actor_id
        ? `https://nextwork-55o.pages.dev/perfil-publico.html?id=${notif.actor_id}`
        : "https://nextwork-55o.pages.dev/dashboard.html";
      previewText = "Ya son conexiones — ahora pueden mensajearse directamente en Nextwork.";
    }
    const ctaLabel = CTA_LABEL[type] || "Ver en Nextwork";

    // El HTML del cuerpo se arma aca y se manda como una sola variable
    // (content_html) -- la plantilla de EmailJS es solo el marco fijo
    // (header/footer), compartido tambien con weekly-digest.
    const contentHtml = `
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td style="padding:36px 32px 4px;text-align:center;">
            <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:0 auto 18px;">
              <tr>
                <td width="56" height="56" align="center" valign="middle" style="width:56px;height:56px;border-radius:50%;background-color:${actorColor};font-family:Georgia,'Times New Roman',serif;font-size:22px;font-weight:bold;color:#ffffff;">${actorInitial}</td>
              </tr>
            </table>
            <p style="margin:0;font-size:16px;line-height:1.6;color:#0f0e0c;"><strong>${actorName}</strong> ${ACTION_TEXT[type]}</p>
          </td>
        </tr>
        <tr>
          <td style="padding:16px 32px 32px;">
            <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f2eb;border-radius:10px;">
              <tr><td style="padding:16px 20px;font-size:13.5px;line-height:1.6;color:#3d3b36;font-style:italic;">"${previewText}"</td></tr>
            </table>
            <table role="presentation" cellpadding="0" cellspacing="0" align="center" style="margin:22px auto 0;">
              <tr>
                <td align="center" style="border-radius:22px;background-color:#1a3a2a;">
                  <a href="${actionUrl}" style="display:inline-block;padding:12px 32px;font-size:14px;font-weight:500;color:#c8f0d8;text-decoration:none;border-radius:22px;font-family:'DM Sans',Helvetica,Arial,sans-serif;">${ctaLabel} →</a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>`;

    const res = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
      method: "POST",
      headers: { "Content-Type": "application/json", origin: "https://nextwork-55o.pages.dev" },
      body: JSON.stringify({
        service_id: EMAILJS_SERVICE_ID,
        template_id: Deno.env.get("EMAILJS_TEMPLATE_ID"),
        user_id: EMAILJS_PUBLIC_KEY,
        template_params: {
          to_email: recipient.email,
          to_name: recipient.name || "",
          subject: `${actorName} interactuó contigo en Nextwork`,
          content_html: contentHtml,
        },
      }),
    });

    return new Response(JSON.stringify({ sent: res.ok }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
