-- Limite anti-spam, reportes de contenido y comentarios reales
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- ═══ LIMITE ANTI-SPAM (publicaciones y oportunidades) ═══
CREATE OR REPLACE FUNCTION public.check_post_rate_limit()
RETURNS trigger AS $$
BEGIN
  IF (SELECT count(*) FROM public.posts WHERE author_id = NEW.author_id AND created_at > now() - interval '10 minutes') >= 5 THEN
    RAISE EXCEPTION 'Estás publicando muy rápido. Espera unos minutos antes de volver a publicar.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER posts_rate_limit
  BEFORE INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.check_post_rate_limit();

CREATE OR REPLACE FUNCTION public.check_opportunity_rate_limit()
RETURNS trigger AS $$
BEGIN
  IF (SELECT count(*) FROM public.opportunities WHERE author_id = NEW.author_id AND created_at > now() - interval '30 minutes') >= 3 THEN
    RAISE EXCEPTION 'Has publicado demasiadas oportunidades en poco tiempo. Intenta más tarde.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER opportunities_rate_limit
  BEFORE INSERT ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.check_opportunity_rate_limit();


-- ═══ REPORTES DE CONTENIDO ═══
CREATE TABLE public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users(id) on delete cascade not null,
  content_type text not null check (content_type in ('post','opportunity','profile')),
  content_id uuid not null,
  reason text not null check (char_length(trim(reason)) between 3 and 500),
  created_at timestamptz default now()
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Solo insertar como uno mismo. Sin politica de SELECT: el equipo revisa
-- los reportes directamente desde el Table Editor de Supabase (rol admin
-- pasa por encima de RLS), nadie mas puede leer quien reporto que.
CREATE POLICY "Reportar como uno mismo"
  ON public.reports FOR INSERT TO public
  WITH CHECK (auth.uid() = reporter_id);


-- ═══ COMENTARIOS EN PUBLICACIONES ═══
CREATE TABLE public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade not null,
  author_id uuid references auth.users(id) on delete cascade not null,
  body text not null check (char_length(trim(body)) between 1 and 500),
  created_at timestamptz default now()
);

ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede leer comentarios"
  ON public.comments FOR SELECT TO public USING (true);

CREATE POLICY "Comentar como uno mismo"
  ON public.comments FOR INSERT TO public
  WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Solo el autor borra su comentario"
  ON public.comments FOR DELETE TO public
  USING (auth.uid() = author_id);
