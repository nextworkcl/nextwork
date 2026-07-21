-- Sistema de postulaciones a oportunidades
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.applications (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid references public.opportunities(id) on delete cascade not null,
  applicant_id uuid references auth.users(id) on delete cascade not null,
  message text check (char_length(trim(message)) <= 1000),
  status text not null default 'pending' check (status in ('pending','accepted','rejected')),
  created_at timestamptz default now(),
  responded_at timestamptz,
  unique(opportunity_id, applicant_id)
);

ALTER TABLE public.applications ENABLE ROW LEVEL SECURITY;

-- El postulante ve sus propias postulaciones; el dueño de la oportunidad
-- ve todas las postulaciones que recibio
CREATE POLICY "Ver postulaciones propias o de mi oportunidad"
  ON public.applications FOR SELECT TO public
  USING (
    auth.uid() = applicant_id
    OR EXISTS (SELECT 1 FROM public.opportunities WHERE id = opportunity_id AND author_id = auth.uid())
  );

CREATE POLICY "Postular como uno mismo"
  ON public.applications FOR INSERT TO public
  WITH CHECK (auth.uid() = applicant_id);

-- Solo el dueño de la oportunidad puede aceptar/rechazar
CREATE POLICY "Dueño de la oportunidad responde postulaciones"
  ON public.applications FOR UPDATE TO public
  USING (EXISTS (SELECT 1 FROM public.opportunities WHERE id = opportunity_id AND author_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.opportunities WHERE id = opportunity_id AND author_id = auth.uid()));

-- El postulante puede retirar su propia postulacion
CREATE POLICY "Retirar mi propia postulacion"
  ON public.applications FOR DELETE TO public
  USING (auth.uid() = applicant_id);

-- No se puede postular a la propia oportunidad
CREATE OR REPLACE FUNCTION public.check_not_self_apply()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE opp_author uuid;
BEGIN
  SELECT author_id INTO opp_author FROM public.opportunities WHERE id = NEW.opportunity_id;
  IF opp_author = NEW.applicant_id THEN
    RAISE EXCEPTION 'No puedes postular a tu propia oportunidad.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER applications_check_self
  BEFORE INSERT ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.check_not_self_apply();

-- Limite anti-spam
CREATE OR REPLACE FUNCTION public.check_application_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT count(*) FROM public.applications WHERE applicant_id = NEW.applicant_id AND created_at > now() - interval '1 hour') >= 15 THEN
    RAISE EXCEPTION 'Has postulado a muchas oportunidades en poco tiempo. Espera un poco.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER applications_rate_limit
  BEFORE INSERT ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.check_application_rate_limit();

-- Agrega los tipos de notificacion de postulaciones
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
  CHECK (type in ('connection_request','connection_accepted','post_like','post_comment','message','application_received','application_accepted','application_rejected'));

CREATE OR REPLACE FUNCTION public.notify_application_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE opp_author uuid;
BEGIN
  SELECT author_id INTO opp_author FROM public.opportunities WHERE id = NEW.opportunity_id;
  IF opp_author IS NOT NULL THEN
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (opp_author, NEW.applicant_id, 'application_received', NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER applications_notify_received
  AFTER INSERT ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.notify_application_received();

CREATE OR REPLACE FUNCTION public.notify_application_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE opp_author uuid;
BEGIN
  IF NEW.status <> OLD.status AND NEW.status IN ('accepted','rejected') THEN
    SELECT author_id INTO opp_author FROM public.opportunities WHERE id = NEW.opportunity_id;
    INSERT INTO public.notifications (recipient_id, actor_id, type, entity_id)
    VALUES (NEW.applicant_id, opp_author, 'application_'||NEW.status, NEW.id);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER applications_notify_status
  AFTER UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.notify_application_status();
