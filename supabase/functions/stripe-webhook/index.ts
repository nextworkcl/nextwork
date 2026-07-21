// Supabase Edge Function: recibe los eventos de Stripe y activa/desactiva
// el plan Pro del usuario correspondiente.
//
// Deploy (OJO con --no-verify-jwt: Stripe no manda un JWT de Supabase,
// esta funcion verifica la firma del webhook por su cuenta):
//   supabase functions deploy stripe-webhook --no-verify-jwt
//
// Configura en Stripe -> Developers -> Webhooks -> Add endpoint:
//   URL: https://<tu-proyecto>.supabase.co/functions/v1/stripe-webhook
//   Eventos a escuchar: checkout.session.completed,
//     customer.subscription.updated, customer.subscription.deleted
//
// Secrets necesarios:
//   STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET (lo da Stripe al crear el
//   endpoint, empieza con whsec_)

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@14?target=deno";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
});
const webhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

serve(async (req) => {
  const signature = req.headers.get("stripe-signature");
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature!, webhookSecret);
  } catch (err) {
    return new Response(`Webhook signature verification failed: ${(err as Error).message}`, { status: 400 });
  }

  try {
    if (event.type === "checkout.session.completed") {
      const session = event.data.object as Stripe.Checkout.Session;
      const userId = session.metadata?.supabase_user_id;
      if (userId && session.subscription) {
        const subscription = await stripe.subscriptions.retrieve(session.subscription as string);
        await supabase.from("profiles").update({
          pro_active: true,
          pro_current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
        }).eq("id", userId);
      }
    }

    if (event.type === "customer.subscription.updated" || event.type === "customer.subscription.deleted") {
      const subscription = event.data.object as Stripe.Subscription;
      const customerId = subscription.customer as string;
      const isActive = subscription.status === "active" || subscription.status === "trialing";
      await supabase.from("profiles").update({
        pro_active: isActive,
        pro_current_period_end: new Date(subscription.current_period_end * 1000).toISOString(),
      }).eq("stripe_customer_id", customerId);
    }

    return new Response(JSON.stringify({ received: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: (err as Error).message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
