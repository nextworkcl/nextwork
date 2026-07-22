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
//   1. Crea una plantilla nueva (Email Templates -> Create New Template).
//      Pega el HTML que esta en email-templates/notificacion.html (editor
//      de EmailJS -> boton "</> Code Editor" para pegar HTML crudo) --
//      usa estas variables exactas: {{to_email}}, {{to_name}},
//      {{actor_name}}, {{actor_initial}}, {{actor_color}}, {{action_text}},
//      {{preview_text}}, {{action_url}}, {{cta_label}}
//   2. Copia el Template ID y ponlo como secret EMAILJS_NOTIF_TEMPLATE_ID
//   3. Confirma que "Allow requests from non-browser applications" siga
//      activado en Account -> Security (ya deberia estarlo desde el
//      resumen semanal, sql/push_and_digest.sql)
//
// Secrets necesarios: EMAILJS_NOTIF_TEMPLATE_ID
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

    const res = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
      method: "POST",
      headers: { "Content-Type": "application/json", origin: "https://nextwork-55o.pages.dev" },
      body: JSON.stringify({
        service_id: EMAILJS_SERVICE_ID,
        template_id: Deno.env.get("EMAILJS_NOTIF_TEMPLATE_ID"),
        user_id: EMAILJS_PUBLIC_KEY,
        template_params: {
          to_email: recipient.email,
          to_name: recipient.name || "",
          actor_name: actorName,
          actor_initial: actorInitial,
          actor_color: actorColor,
          action_text: ACTION_TEXT[type],
          preview_text: previewText,
          action_url: actionUrl,
          cta_label: CTA_LABEL[type] || "Ver en Nextwork",
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
