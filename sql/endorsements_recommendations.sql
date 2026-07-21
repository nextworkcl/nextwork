-- Endorsements de habilidades + recomendaciones escritas
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- ═══ AVALES DE HABILIDADES ═══
CREATE TABLE public.skill_endorsements (
  id uuid primary key default gen_random_uuid(),
  endorser_id uuid references auth.users(id) on delete cascade not null,
  endorsed_id uuid references auth.users(id) on delete cascade not null,
  skill text not null check (char_length(trim(skill)) between 1 and 60),
  created_at timestamptz default now(),
  unique(endorser_id, endorsed_id, skill),
  constraint no_self_endorse check (endorser_id <> endorsed_id)
);

ALTER TABLE public.skill_endorsements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede ver avales"
  ON public.skill_endorsements FOR SELECT TO public USING (true);

-- Solo puedes avalar a una conexion aceptada
CREATE POLICY "Avalar como uno mismo a una conexion"
  ON public.skill_endorsements FOR INSERT TO public
  WITH CHECK (
    auth.uid() = endorser_id
    AND EXISTS (
      SELECT 1 FROM public.connections
      WHERE status = 'accepted'
        AND ((from_id = endorser_id AND to_id = endorsed_id)
          OR (from_id = endorsed_id AND to_id = endorser_id))
    )
  );

CREATE POLICY "Quitar mi propio aval"
  ON public.skill_endorsements FOR DELETE TO public
  USING (auth.uid() = endorser_id);

-- Solo se puede avalar una habilidad que la persona realmente tiene listada
CREATE OR REPLACE FUNCTION public.check_endorsement_skill_valid()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = NEW.endorsed_id AND NEW.skill = ANY(skills)
  ) THEN
    RAISE EXCEPTION 'Esa habilidad no está en el perfil de esta persona.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER skill_endorsements_check_skill
  BEFORE INSERT ON public.skill_endorsements
  FOR EACH ROW EXECUTE FUNCTION public.check_endorsement_skill_valid();


-- ═══ RECOMENDACIONES ESCRITAS ═══
CREATE TABLE public.recommendations (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references auth.users(id) on delete cascade not null,
  recipient_id uuid references auth.users(id) on delete cascade not null,
  body text not null check (char_length(trim(body)) between 20 and 2000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz default now(),
  responded_at timestamptz,
  constraint no_self_recommend check (author_id <> recipient_id)
);

ALTER TABLE public.recommendations ENABLE ROW LEVEL SECURITY;

-- Publico solo ve las aprobadas; autor y destinatario ven la suya en cualquier estado
CREATE POLICY "Ver recomendaciones aprobadas o propias"
  ON public.recommendations FOR SELECT TO public
  USING (status = 'approved' OR auth.uid() = author_id OR auth.uid() = recipient_id);

CREATE POLICY "Escribir recomendacion a una conexion"
  ON public.recommendations FOR INSERT TO public
  WITH CHECK (
    auth.uid() = author_id
    AND EXISTS (
      SELECT 1 FROM public.connections
      WHERE status = 'accepted'
        AND ((from_id = author_id AND to_id = recipient_id)
          OR (from_id = recipient_id AND to_id = author_id))
    )
  );

-- Solo el destinatario aprueba/rechaza (asi nadie puede publicar algo negativo
-- en tu perfil sin que tu decidas mostrarlo)
CREATE POLICY "Destinatario aprueba o rechaza"
  ON public.recommendations FOR UPDATE TO public
  USING (auth.uid() = recipient_id)
  WITH CHECK (auth.uid() = recipient_id);

CREATE POLICY "Autor retira su recomendacion"
  ON public.recommendations FOR DELETE TO public
  USING (auth.uid() = author_id);


-- ═══ NOTIFICACIONES ═══
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
    'skill_endorsed','recommendation_received','recommendation_approved'));

CREATE OR REPLACE FUNCTION public.notify_skill_endorsed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
  VALUES (NEW.endorsed_id, NEW.endorser_id, 'skill_endorsed', NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER skill_endorsements_notify
  AFTER INSERT ON public.skill_endorsements
  FOR EACH ROW EXECUTE FUNCTION public.notify_skill_endorsed();

CREATE OR REPLACE FUNCTION public.notify_recommendation_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
  VALUES (NEW.recipient_id, NEW.author_id, 'recommendation_received', NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER recommendations_notify_received
  AFTER INSERT ON public.recommendations
  FOR EACH ROW EXECUTE FUNCTION public.notify_recommendation_received();

CREATE OR REPLACE FUNCTION public.notify_recommendation_approved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved' THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (NEW.author_id, NEW.recipient_id, 'recommendation_approved', NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER recommendations_notify_approved
  AFTER UPDATE ON public.recommendations
  FOR EACH ROW EXECUTE FUNCTION public.notify_recommendation_approved();
