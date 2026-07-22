-- URGENTE: corrige "infinite recursion detected in policy for relation
-- group_members" (Postgres 42P17), que esta rompiendo Grupos, Eventos y
-- el modo grupo de Comunidad en produccion ahora mismo.
--
-- Causa: la politica de SELECT de group_members se consultaba a si misma
-- dentro de su propia condicion (para revisar si sos miembro aprobado),
-- y varias politicas de groups/posts/events/event_rsvps tambien hacian
-- EXISTS (SELECT ... FROM group_members ...) directo. Cuando Postgres
-- evalua una politica RLS, cualquier tabla que esa politica consulte
-- vuelve a pasar por sus propias politicas -- así que la subconsulta a
-- group_members dentro de la politica de group_members se llamaba a si
-- misma sin parar.
--
-- Fix: dos funciones SECURITY DEFINER (mismo patron ya usado en
-- is_blocked_between) que consultan group_members saltandose RLS, y se
-- usan desde todas las politicas en vez de la subconsulta directa.
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE OR REPLACE FUNCTION public.is_approved_group_member(gid uuid, uid uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = gid AND user_id = uid AND status = 'approved'
  );
$$;

CREATE OR REPLACE FUNCTION public.is_group_admin(gid uuid, uid uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = gid AND user_id = uid AND role = 'admin' AND status = 'approved'
  );
$$;


-- ═══ group_members ═══
DROP POLICY "Ver miembros segun visibilidad" ON public.group_members;
CREATE POLICY "Ver miembros segun visibilidad"
  ON public.group_members FOR SELECT TO public
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = group_members.group_id AND g.is_private = false)
    OR public.is_approved_group_member(group_members.group_id, auth.uid())
  );

DROP POLICY "Admins gestionan membresias" ON public.group_members;
CREATE POLICY "Admins gestionan membresias"
  ON public.group_members FOR UPDATE TO public
  USING (public.is_group_admin(group_members.group_id, auth.uid()))
  WITH CHECK (public.is_group_admin(group_members.group_id, auth.uid()));

DROP POLICY "Salir del grupo o admin expulsa" ON public.group_members;
CREATE POLICY "Salir del grupo o admin expulsa"
  ON public.group_members FOR DELETE TO public
  USING (
    user_id = auth.uid()
    OR public.is_group_admin(group_members.group_id, auth.uid())
  );


-- ═══ groups ═══
DROP POLICY "Admins editan el grupo" ON public.groups;
CREATE POLICY "Admins editan el grupo"
  ON public.groups FOR UPDATE TO public
  USING (public.is_group_admin(groups.id, auth.uid()))
  WITH CHECK (public.is_group_admin(groups.id, auth.uid()));


-- ═══ posts ═══
DROP POLICY "Leer publicaciones segun visibilidad" ON public.posts;
CREATE POLICY "Leer publicaciones segun visibilidad"
  ON public.posts FOR SELECT TO public
  USING (
    group_id IS NULL
    OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = posts.group_id AND g.is_private = false)
    OR public.is_approved_group_member(posts.group_id, auth.uid())
  );

DROP POLICY "Publicar en el feed o en grupos donde soy miembro" ON public.posts;
CREATE POLICY "Publicar en el feed o en grupos donde soy miembro"
  ON public.posts FOR INSERT TO public
  WITH CHECK (
    auth.uid() = author_id
    AND (group_id IS NULL OR public.is_approved_group_member(posts.group_id, auth.uid()))
  );

DROP POLICY "Autor o admin del grupo borra la publicacion" ON public.posts;
CREATE POLICY "Autor o admin del grupo borra la publicacion"
  ON public.posts FOR DELETE TO public
  USING (
    auth.uid() = author_id
    OR (group_id IS NOT NULL AND public.is_group_admin(posts.group_id, auth.uid()))
  );


-- ═══ events ═══
DROP POLICY "Leer eventos segun visibilidad" ON public.events;
CREATE POLICY "Leer eventos segun visibilidad"
  ON public.events FOR SELECT TO public
  USING (
    group_id IS NULL
    OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = events.group_id AND g.is_private = false)
    OR public.is_approved_group_member(events.group_id, auth.uid())
  );

DROP POLICY "Crear evento como uno mismo" ON public.events;
CREATE POLICY "Crear evento como uno mismo"
  ON public.events FOR INSERT TO public
  WITH CHECK (
    auth.uid() = creator_id
    AND (group_id IS NULL OR public.is_approved_group_member(events.group_id, auth.uid()))
  );

DROP POLICY "Autor o admin del grupo borra el evento" ON public.events;
CREATE POLICY "Autor o admin del grupo borra el evento"
  ON public.events FOR DELETE TO public
  USING (
    auth.uid() = creator_id
    OR (group_id IS NOT NULL AND public.is_group_admin(events.group_id, auth.uid()))
  );


-- ═══ event_rsvps ═══
DROP POLICY "Ver rsvps de eventos visibles" ON public.event_rsvps;
CREATE POLICY "Ver rsvps de eventos visibles"
  ON public.event_rsvps FOR SELECT TO public
  USING (
    EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_rsvps.event_id
      AND (
        e.group_id IS NULL
        OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = e.group_id AND g.is_private = false)
        OR public.is_approved_group_member(e.group_id, auth.uid())
      )
    )
  );

DROP POLICY "Responder RSVP como uno mismo" ON public.event_rsvps;
CREATE POLICY "Responder RSVP como uno mismo"
  ON public.event_rsvps FOR INSERT TO public
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_rsvps.event_id
      AND (
        e.group_id IS NULL
        OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = e.group_id AND g.is_private = false)
        OR public.is_approved_group_member(e.group_id, auth.uid())
      )
    )
  );

DROP POLICY "Cambiar mi propio RSVP" ON public.event_rsvps;
CREATE POLICY "Cambiar mi propio RSVP"
  ON public.event_rsvps FOR UPDATE TO public
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_rsvps.event_id
      AND (
        e.group_id IS NULL
        OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = e.group_id AND g.is_private = false)
        OR public.is_approved_group_member(e.group_id, auth.uid())
      )
    )
  );
