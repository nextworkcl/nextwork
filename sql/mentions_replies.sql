-- Menciones (@usuario) en publicaciones/comentarios + respuestas anidadas
-- Ejecutar completo en Supabase -> SQL Editor -> Run

ALTER TABLE public.posts ADD COLUMN mentions uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE public.comments ADD COLUMN mentions uuid[] NOT NULL DEFAULT '{}';
ALTER TABLE public.comments ADD COLUMN parent_id uuid REFERENCES public.comments(id) ON DELETE CASCADE;

-- ═══ NUEVOS TIPOS DE NOTIFICACION ═══
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
  CHECK (type in ('connection_request','connection_accepted','post_like','post_comment','message',
    'application_received','application_accepted','application_rejected',
    'skill_endorsed','recommendation_received','recommendation_approved',
    'mention','comment_reply'));

-- ═══ MENCIONES EN PUBLICACIONES ═══
CREATE OR REPLACE FUNCTION public.check_post_mentions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF coalesce(array_length(NEW.mentions,1),0) > 10 THEN
    RAISE EXCEPTION 'No puedes mencionar a más de 10 personas.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER posts_check_mentions
  BEFORE INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.check_post_mentions();

-- Notifica solo a menciones que sean conexiones aceptadas del autor
-- (evita que se pueda spamear a desconocidos metiendo ids a mano)
CREATE OR REPLACE FUNCTION public.notify_post_mentions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
  SELECT DISTINCT m, NEW.author_id, 'mention', NEW.id
  FROM unnest(NEW.mentions) AS m
  WHERE m <> NEW.author_id
    AND EXISTS (
      SELECT 1 FROM public.connections
      WHERE status = 'accepted'
        AND ((from_id = NEW.author_id AND to_id = m) OR (from_id = m AND to_id = NEW.author_id))
    );
  RETURN NEW;
END;
$$;

CREATE TRIGGER posts_notify_mentions
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_post_mentions();

-- ═══ RESPUESTAS ANIDADAS + MENCIONES EN COMENTARIOS ═══
-- Un solo nivel de anidacion (estilo LinkedIn): responder a una respuesta
-- cuelga del comentario raiz del hilo
CREATE OR REPLACE FUNCTION public.check_comment_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE parent_row public.comments%ROWTYPE;
BEGIN
  IF coalesce(array_length(NEW.mentions,1),0) > 10 THEN
    RAISE EXCEPTION 'No puedes mencionar a más de 10 personas.';
  END IF;
  IF NEW.parent_id IS NOT NULL THEN
    SELECT * INTO parent_row FROM public.comments WHERE id = NEW.parent_id;
    IF parent_row.id IS NULL OR parent_row.post_id <> NEW.post_id THEN
      RAISE EXCEPTION 'Comentario padre inválido.';
    END IF;
    IF parent_row.parent_id IS NOT NULL THEN
      NEW.parent_id := parent_row.parent_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER comments_check_insert
  BEFORE INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.check_comment_insert();

-- Notifica: respuesta al autor del hilo + menciones (conexiones del autor,
-- o participantes de la misma publicacion, para poder responderle a alguien
-- que comento sin ser tu conexion)
CREATE OR REPLACE FUNCTION public.notify_comment_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE parent_author uuid;
BEGIN
  INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
  SELECT DISTINCT m, NEW.author_id, 'mention', NEW.id
  FROM unnest(NEW.mentions) AS m
  WHERE m <> NEW.author_id
    AND (
      EXISTS (SELECT 1 FROM public.connections
        WHERE status = 'accepted'
          AND ((from_id = NEW.author_id AND to_id = m) OR (from_id = m AND to_id = NEW.author_id)))
      OR EXISTS (SELECT 1 FROM public.posts WHERE id = NEW.post_id AND author_id = m)
      OR EXISTS (SELECT 1 FROM public.comments c2 WHERE c2.post_id = NEW.post_id AND c2.author_id = m)
    );

  IF NEW.parent_id IS NOT NULL THEN
    SELECT author_id INTO parent_author FROM public.comments WHERE id = NEW.parent_id;
    IF parent_author IS NOT NULL AND parent_author <> NEW.author_id
       AND NOT (parent_author = ANY(NEW.mentions)) THEN
      INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
      VALUES (parent_author, NEW.author_id, 'comment_reply', NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER comments_notify_insert
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_comment_insert();
