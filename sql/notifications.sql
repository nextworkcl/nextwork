-- Notificaciones reales (solicitudes, conexiones aceptadas, likes, comentarios)
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid references auth.users(id) on delete cascade not null,
  actor_id uuid references auth.users(id) on delete cascade,
  type text not null check (type in ('connection_request','connection_accepted','post_like','post_comment')),
  entity_id uuid,
  read boolean not null default false,
  created_at timestamptz default now()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Nadie inserta notificaciones directamente: solo los triggers de abajo
-- (corren como SECURITY DEFINER, saltan RLS). Los usuarios solo pueden
-- leer y marcar como leidas las suyas.
CREATE POLICY "Ver mis propias notificaciones"
  ON public.notifications FOR SELECT TO public
  USING (auth.uid() = recipient_id);

CREATE POLICY "Marcar mis notificaciones como leidas"
  ON public.notifications FOR UPDATE TO public
  USING (auth.uid() = recipient_id)
  WITH CHECK (auth.uid() = recipient_id);


-- ═══ Nueva solicitud de conexion ═══
CREATE OR REPLACE FUNCTION public.notify_connection_request()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
  VALUES (NEW.to_id, NEW.from_id, 'connection_request', NEW.id);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER connections_notify_request
  AFTER INSERT ON public.connections
  FOR EACH ROW EXECUTE FUNCTION public.notify_connection_request();


-- ═══ Solicitud aceptada ═══
CREATE OR REPLACE FUNCTION public.notify_connection_accepted()
RETURNS trigger AS $$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted' THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (NEW.from_id, NEW.to_id, 'connection_accepted', NEW.id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER connections_notify_accept
  AFTER UPDATE ON public.connections
  FOR EACH ROW EXECUTE FUNCTION public.notify_connection_accepted();


-- ═══ Like en una publicacion ═══
CREATE OR REPLACE FUNCTION public.notify_post_like()
RETURNS trigger AS $$
DECLARE post_author uuid;
BEGIN
  SELECT author_id INTO post_author FROM public.posts WHERE id = NEW.post_id;
  IF post_author IS NOT NULL AND post_author <> NEW.user_id THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (post_author, NEW.user_id, 'post_like', NEW.post_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER post_likes_notify
  AFTER INSERT ON public.post_likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_post_like();


-- ═══ Comentario en una publicacion ═══
CREATE OR REPLACE FUNCTION public.notify_post_comment()
RETURNS trigger AS $$
DECLARE post_author uuid;
BEGIN
  SELECT author_id INTO post_author FROM public.posts WHERE id = NEW.post_id;
  IF post_author IS NOT NULL AND post_author <> NEW.author_id THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (post_author, NEW.author_id, 'post_comment', NEW.post_id);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER comments_notify
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_post_comment();
