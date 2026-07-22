-- Auditoria de seguridad post-Grupos/Eventos: limites anti-spam que
-- faltaban y un endurecimiento de RLS en el UPDATE de event_rsvps.
-- Ejecutar completo en Supabase -> SQL Editor -> Run
-- (requiere que ya hayas corrido sql/groups.sql y sql/events.sql)

-- ═══ LIMITE ANTI-SPAM: creacion de grupos y eventos ═══
-- (mismo patron ya usado para publicaciones/oportunidades)
CREATE OR REPLACE FUNCTION public.check_group_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT count(*) FROM public.groups WHERE creator_id = NEW.creator_id AND created_at > now() - interval '1 hour') >= 3 THEN
    RAISE EXCEPTION 'Estás creando demasiados grupos. Espera un poco antes de crear otro.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER groups_rate_limit
  BEFORE INSERT ON public.groups
  FOR EACH ROW EXECUTE FUNCTION public.check_group_rate_limit();

CREATE OR REPLACE FUNCTION public.check_event_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT count(*) FROM public.events WHERE creator_id = NEW.creator_id AND created_at > now() - interval '1 hour') >= 5 THEN
    RAISE EXCEPTION 'Estás creando demasiados eventos. Espera un poco antes de crear otro.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER events_rate_limit
  BEFORE INSERT ON public.events
  FOR EACH ROW EXECUTE FUNCTION public.check_event_rate_limit();


-- ═══ ENDURECER RLS: UPDATE de event_rsvps ═══
-- La politica original solo validaba que la fila fuera del usuario
-- (user_id = auth.uid()), sin revalidar que el evento destino siga
-- siendo visible para el si el UPDATE le cambia el event_id. En la
-- practica el frontend nunca reasigna event_id (solo status), pero un
-- cliente hablando directo con la API podria "mover" su propio RSVP a
-- cualquier event_id adivinando un uuid. Se cierra con el mismo chequeo
-- de visibilidad que ya usa el INSERT.
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
        OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = e.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved')
      )
    )
  );
