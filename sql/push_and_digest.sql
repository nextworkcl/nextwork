-- Notificaciones push del navegador + resumen semanal por correo
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  endpoint text not null,
  p256dh text not null,
  auth text not null,
  created_at timestamptz default now(),
  unique(user_id, endpoint)
);

ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ver mis propias suscripciones push"
  ON public.push_subscriptions FOR SELECT TO public
  USING (auth.uid() = user_id);

CREATE POLICY "Crear mi propia suscripcion push"
  ON public.push_subscriptions FOR INSERT TO public
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Borrar mi propia suscripcion push"
  ON public.push_subscriptions FOR DELETE TO public
  USING (auth.uid() = user_id);

-- Permite optar por no recibir el resumen semanal por correo
ALTER TABLE public.profiles ADD COLUMN email_digest_opt_out boolean NOT NULL DEFAULT false;
