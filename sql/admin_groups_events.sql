-- Permite reportar grupos y eventos, y que un admin de plataforma pueda
-- eliminar cualquier grupo/evento (hoy solo podia el creador, o un admin
-- del grupo en el caso de eventos -- ningun admin de plataforma tenia
-- forma de bajar un grupo o evento problematico sin entrar a Supabase
-- directamente).
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- (busca el nombre real de la constraint en vez de asumirlo, por si
-- Postgres la nombro distinto -- mismo patron usado en sql/groups.sql)
DO $$
DECLARE con_name text;
BEGIN
  SELECT conname INTO con_name FROM pg_constraint
  WHERE conrelid = 'public.reports'::regclass AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%content_type%';
  IF con_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.reports DROP CONSTRAINT %I', con_name);
  END IF;
END $$;

ALTER TABLE public.reports ADD CONSTRAINT reports_content_type_check
  CHECK (content_type in ('post','opportunity','profile','group','event'));

CREATE POLICY "Admins borran cualquier grupo"
  ON public.groups FOR DELETE TO public
  USING (EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));

CREATE POLICY "Admins borran cualquier evento"
  ON public.events FOR DELETE TO public
  USING (EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true));
