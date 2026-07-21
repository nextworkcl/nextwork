-- Comunidades (grupos profesionales por industria/interes)
-- Reutiliza el motor de publicaciones/likes/comentarios existente: los posts
-- de un grupo son filas normales de public.posts con group_id seteado.
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- ═══ GRUPOS ═══
CREATE TABLE public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 3 and 80),
  description text not null default '' check (char_length(description) <= 500),
  category text not null default 'general' check (category in ('general','startups','tecnologia','diseno','inversion','marketing','producto','ventas')),
  color text not null default '#2d6b4a',
  cover_image text,
  creator_id uuid references auth.users(id) on delete cascade not null,
  is_private boolean not null default false,
  member_count int not null default 0,
  created_at timestamptz default now()
);

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede leer grupos"
  ON public.groups FOR SELECT TO public USING (true);

CREATE POLICY "Crear grupo como uno mismo"
  ON public.groups FOR INSERT TO public
  WITH CHECK (auth.uid() = creator_id);

CREATE POLICY "Admins editan el grupo"
  ON public.groups FOR UPDATE TO public
  USING (EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = groups.id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = groups.id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved'));

CREATE POLICY "Solo el creador borra el grupo"
  ON public.groups FOR DELETE TO public
  USING (auth.uid() = creator_id);

-- member_count solo lo mantiene el trigger de abajo, nunca el cliente
REVOKE UPDATE (member_count) ON public.groups FROM authenticated, anon;


-- ═══ MIEMBROS DE GRUPO ═══
CREATE TABLE public.group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid references public.groups(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  role text not null default 'member' check (role in ('admin','member')),
  status text not null check (status in ('approved','pending')),
  joined_at timestamptz default now(),
  unique (group_id, user_id)
);

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
CREATE INDEX idx_group_members_user_id ON public.group_members(user_id);
CREATE INDEX idx_posts_group_id ON public.posts(group_id);

CREATE POLICY "Ver miembros segun visibilidad"
  ON public.group_members FOR SELECT TO public
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = group_members.group_id AND g.is_private = false)
    OR EXISTS (SELECT 1 FROM public.group_members gm2 WHERE gm2.group_id = group_members.group_id AND gm2.user_id = auth.uid() AND gm2.status = 'approved')
  );

-- El rol siempre debe declararse 'member' desde el cliente -- el trigger de
-- abajo calcula el estado real (approved/pending) segun la privacidad del
-- grupo y lo sobreescribe sin importar lo que mande el cliente. La unica
-- forma de insertar una fila con role='admin' es el trigger de creacion de
-- grupo (corre como SECURITY DEFINER y salta esta politica).
CREATE POLICY "Unirse a un grupo"
  ON public.group_members FOR INSERT TO public
  WITH CHECK (user_id = auth.uid() AND role = 'member');

CREATE POLICY "Admins gestionan membresias"
  ON public.group_members FOR UPDATE TO public
  USING (EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = group_members.group_id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = group_members.group_id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved'));

CREATE POLICY "Salir del grupo o admin expulsa"
  ON public.group_members FOR DELETE TO public
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = group_members.group_id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved')
  );


-- ═══ COLUMNA group_id EN POSTS (null = feed principal) ═══
ALTER TABLE public.posts ADD COLUMN group_id uuid references public.groups(id) on delete cascade;

DROP POLICY "Cualquiera puede leer publicaciones" ON public.posts;
CREATE POLICY "Leer publicaciones segun visibilidad"
  ON public.posts FOR SELECT TO public
  USING (
    group_id IS NULL
    OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = posts.group_id AND g.is_private = false)
    OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = posts.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved')
  );

DROP POLICY "Publicar como uno mismo" ON public.posts;
CREATE POLICY "Publicar en el feed o en grupos donde soy miembro"
  ON public.posts FOR INSERT TO public
  WITH CHECK (
    auth.uid() = author_id
    AND (group_id IS NULL OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = posts.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved'))
  );

DROP POLICY "Solo el autor borra su publicacion" ON public.posts;
CREATE POLICY "Autor o admin del grupo borra la publicacion"
  ON public.posts FOR DELETE TO public
  USING (
    auth.uid() = author_id
    OR (group_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = posts.group_id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved'))
  );


-- ═══ TRIGGERS ═══

-- El creador del grupo queda como admin aprobado automaticamente
CREATE OR REPLACE FUNCTION public.groups_add_creator_as_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.group_members (group_id, user_id, role, status)
  VALUES (NEW.id, NEW.creator_id, 'admin', 'approved');
  RETURN NEW;
END;
$$;

CREATE TRIGGER groups_creator_admin
  AFTER INSERT ON public.groups
  FOR EACH ROW EXECUTE FUNCTION public.groups_add_creator_as_admin();

-- Calcula el estado real de una membresia: si la fila viene con role='admin'
-- (solo posible via el trigger de arriba, que salta RLS) queda aprobada de
-- inmediato; cualquier otra fila (las que insertan los usuarios al unirse)
-- se fuerza a role='member' y su status depende de si el grupo es privado
CREATE OR REPLACE FUNCTION public.set_group_member_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE is_priv boolean;
BEGIN
  IF NEW.role = 'admin' THEN
    NEW.status := 'approved';
    RETURN NEW;
  END IF;
  NEW.role := 'member';
  SELECT is_private INTO is_priv FROM public.groups WHERE id = NEW.group_id;
  NEW.status := CASE WHEN is_priv THEN 'pending' ELSE 'approved' END;
  RETURN NEW;
END;
$$;

CREATE TRIGGER group_members_set_status
  BEFORE INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.set_group_member_status();

-- No dejar que el ultimo administrador se salga (o sea expulsado) dejando el
-- grupo huerfano. Se ignora si el grupo entero se esta borrando (cascade).
CREATE OR REPLACE FUNCTION public.check_last_admin_leaving()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE admin_count int;
BEGIN
  IF OLD.role = 'admin' AND EXISTS (SELECT 1 FROM public.groups WHERE id = OLD.group_id) THEN
    SELECT count(*) INTO admin_count FROM public.group_members
    WHERE group_id = OLD.group_id AND role = 'admin' AND status = 'approved';
    IF admin_count <= 1 THEN
      RAISE EXCEPTION 'No puedes salir: eres el único administrador de este grupo. Asciende a otro miembro primero.';
    END IF;
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER group_members_check_last_admin
  BEFORE DELETE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.check_last_admin_leaving();

-- Mantiene groups.member_count sincronizado con las membresias aprobadas
CREATE OR REPLACE FUNCTION public.update_group_member_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'approved' THEN
      UPDATE public.groups SET member_count = member_count + 1 WHERE id = NEW.group_id;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF OLD.status <> 'approved' AND NEW.status = 'approved' THEN
      UPDATE public.groups SET member_count = member_count + 1 WHERE id = NEW.group_id;
    ELSIF OLD.status = 'approved' AND NEW.status <> 'approved' THEN
      UPDATE public.groups SET member_count = greatest(member_count - 1, 0) WHERE id = NEW.group_id;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF OLD.status = 'approved' THEN
      UPDATE public.groups SET member_count = greatest(member_count - 1, 0) WHERE id = OLD.group_id;
    END IF;
  END IF;
  RETURN NULL;
END;
$$;

CREATE TRIGGER group_members_count_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.update_group_member_count();


-- ═══ NOTIFICACIONES: nuevos tipos ═══
-- (busca el nombre real de la constraint en vez de asumirlo, por si Postgres
-- la nombro distinto, y la reconstruye con todos los tipos usados hoy en la app)
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
  CHECK (type in (
    'connection_request','connection_accepted','post_like','post_comment','message',
    'application_received','application_accepted','application_rejected',
    'skill_endorsed','recommendation_received','recommendation_approved',
    'mention','comment_reply','group_join_request','group_join_approved'
  ));

-- Solicitud de union a un grupo privado: notifica a todos los admins
CREATE OR REPLACE FUNCTION public.notify_group_join_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'pending' THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    SELECT gm.user_id, NEW.user_id, 'group_join_request', NEW.group_id
    FROM public.group_members gm
    WHERE gm.group_id = NEW.group_id AND gm.role = 'admin' AND gm.status = 'approved';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER group_members_notify_request
  AFTER INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_join_request();

-- Solicitud aprobada: notifica a quien se unio
CREATE OR REPLACE FUNCTION public.notify_group_join_approved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status = 'pending' THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (NEW.user_id, auth.uid(), 'group_join_approved', NEW.group_id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER group_members_notify_approved
  AFTER UPDATE ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.notify_group_join_approved();


-- ═══ REALTIME ═══
ALTER PUBLICATION supabase_realtime ADD TABLE public.groups;
ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
