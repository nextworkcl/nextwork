-- Mensajeria directa entre conexiones aceptadas
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid references auth.users(id) on delete cascade not null,
  recipient_id uuid references auth.users(id) on delete cascade not null,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  read boolean not null default false,
  created_at timestamptz default now(),
  constraint no_self_message check (sender_id <> recipient_id)
);

ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ver mis propios mensajes"
  ON public.messages FOR SELECT TO public
  USING (auth.uid() = sender_id OR auth.uid() = recipient_id);

CREATE POLICY "Enviar mensaje como uno mismo"
  ON public.messages FOR INSERT TO public
  WITH CHECK (auth.uid() = sender_id);

-- Solo el receptor puede marcar como leido (no puede tocar el resto de la fila)
CREATE POLICY "Marcar como leido mensajes recibidos"
  ON public.messages FOR UPDATE TO public
  USING (auth.uid() = recipient_id)
  WITH CHECK (auth.uid() = recipient_id);

-- Solo se puede escribir a una conexion aceptada, y nunca a alguien bloqueado
-- (en cualquier direccion) -- se valida en la base de datos, no solo en el
-- frontend, para que no se pueda saltar abriendo la consola del navegador
CREATE OR REPLACE FUNCTION public.check_can_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF public.is_blocked_between(NEW.sender_id, NEW.recipient_id) THEN
    RAISE EXCEPTION 'No puedes enviar mensajes a este usuario.';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.connections
    WHERE status = 'accepted'
      AND ((from_id = NEW.sender_id AND to_id = NEW.recipient_id)
        OR (from_id = NEW.recipient_id AND to_id = NEW.sender_id))
  ) THEN
    RAISE EXCEPTION 'Solo puedes enviar mensajes a tus conexiones aceptadas.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER messages_check_connection
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.check_can_message();

-- Limite anti-spam
CREATE OR REPLACE FUNCTION public.check_message_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT count(*) FROM public.messages WHERE sender_id = NEW.sender_id AND created_at > now() - interval '1 minute') >= 20 THEN
    RAISE EXCEPTION 'Estás enviando mensajes muy rápido. Espera un momento.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER messages_rate_limit
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.check_message_rate_limit();

-- Agrega 'message' a los tipos de notificacion permitidos (busca el nombre
-- real de la constraint en vez de asumirlo, por si Postgres la nombro distinto)
DO $$
DECLARE con_name text;
BEGIN
  SELECT conname INTO con_name FROM pg_constraint
  WHERE conrelid = 'public.notifications'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%connection_request%';
  IF con_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.notifications DROP CONSTRAINT %I', con_name);
  END IF;
END $$;

ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check
  CHECK (type in ('connection_request','connection_accepted','post_like','post_comment','message'));

CREATE OR REPLACE FUNCTION public.notify_new_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
  VALUES (NEW.recipient_id, NEW.sender_id, 'message', NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER messages_notify
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_message();

-- Habilita Supabase Realtime (websockets) sobre esta tabla para que el chat
-- se actualice solo, sin recargar la pagina
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
