-- Bloquear usuarios, panel de administracion de reportes,
-- editar comentarios y hardening de seguridad
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- ═══ BLOQUEAR USUARIOS ═══
CREATE TABLE public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid references auth.users(id) on delete cascade not null,
  blocked_id uuid references auth.users(id) on delete cascade not null,
  created_at timestamptz default now(),
  unique(blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ver mis propios bloqueos"
  ON public.blocked_users FOR SELECT TO public
  USING (auth.uid() = blocker_id);

CREATE POLICY "Bloquear como uno mismo"
  ON public.blocked_users FOR INSERT TO public
  WITH CHECK (auth.uid() = blocker_id);

CREATE POLICY "Desbloquear mis propios bloqueos"
  ON public.blocked_users FOR DELETE TO public
  USING (auth.uid() = blocker_id);

-- Chequeo booleano bidireccional sin revelar quien bloqueo a quien
-- (si A bloqueo a B, ni B puede leer la fila de A por RLS, pero ambos
-- pueden preguntar "¿estamos bloqueados?" y obtener true/false)
CREATE OR REPLACE FUNCTION public.is_blocked_between(user_a uuid, user_b uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT EXISTS(
    SELECT 1 FROM public.blocked_users
    WHERE (blocker_id = user_a AND blocked_id = user_b)
       OR (blocker_id = user_b AND blocked_id = user_a)
  );
$$;

GRANT EXECUTE ON FUNCTION public.is_blocked_between(uuid,uuid) TO anon, authenticated;

-- Evita solicitudes de conexion entre usuarios bloqueados (en cualquier direccion)
CREATE OR REPLACE FUNCTION public.check_not_blocked_for_connection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF public.is_blocked_between(NEW.from_id, NEW.to_id) THEN
    RAISE EXCEPTION 'No puedes enviar una solicitud de conexión a este usuario.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER connections_check_blocked
  BEFORE INSERT ON public.connections
  FOR EACH ROW EXECUTE FUNCTION public.check_not_blocked_for_connection();

-- Limite anti-spam de solicitudes de conexion (no existia hasta ahora)
CREATE OR REPLACE FUNCTION public.check_connection_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT count(*) FROM public.connections WHERE from_id = NEW.from_id AND created_at > now() - interval '1 hour') >= 20 THEN
    RAISE EXCEPTION 'Estás enviando demasiadas solicitudes de conexión. Espera un poco.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER connections_rate_limit
  BEFORE INSERT ON public.connections
  FOR EACH ROW EXECUTE FUNCTION public.check_connection_rate_limit();


-- ═══ PANEL DE ADMINISTRACION DE REPORTES ═══
ALTER TABLE public.profiles ADD COLUMN is_admin boolean NOT NULL DEFAULT false;

-- Impide que un usuario se autoasigne is_admin=true desde el navegador.
-- El UPDATE normal de "editar mi perfil" nunca toca esta columna, asi que
-- esto no rompe nada existente. Para hacer admin a alguien: Table Editor
-- de Supabase -> profiles -> is_admin -> true (a mano, por seguridad).
REVOKE UPDATE (is_admin) ON public.profiles FROM authenticated, anon;

ALTER TABLE public.reports ADD COLUMN status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','resolved','dismissed'));

CREATE POLICY "Admins ven todos los reportes"
  ON public.reports FOR SELECT TO public
  USING (EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));

CREATE POLICY "Admins actualizan reportes"
  ON public.reports FOR UPDATE TO public
  USING (EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true))
  WITH CHECK (EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));


-- ═══ EDITAR COMENTARIOS PROPIOS ═══
CREATE POLICY "Solo el autor edita su comentario"
  ON public.comments FOR UPDATE TO public
  USING (auth.uid() = author_id)
  WITH CHECK (auth.uid() = author_id);


-- ═══ HARDENING: search_path fijo en funciones SECURITY DEFINER existentes ═══
-- Sin esto, Supabase marca estas funciones como "Function Search Path
-- Mutable" en su linter de seguridad: un search_path no fijo en una
-- funcion SECURITY DEFINER puede, en teoria, ser secuestrado si alguien
-- logra crear objetos en un esquema que quede antes en el search_path.
ALTER FUNCTION public.check_post_rate_limit() SET search_path = public, pg_temp;
ALTER FUNCTION public.check_opportunity_rate_limit() SET search_path = public, pg_temp;
ALTER FUNCTION public.notify_connection_request() SET search_path = public, pg_temp;
ALTER FUNCTION public.notify_connection_accepted() SET search_path = public, pg_temp;
ALTER FUNCTION public.notify_post_like() SET search_path = public, pg_temp;
ALTER FUNCTION public.notify_post_comment() SET search_path = public, pg_temp;
