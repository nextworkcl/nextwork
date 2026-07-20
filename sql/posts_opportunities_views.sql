-- Publicaciones reales, oportunidades reales y contador de visitas al perfil
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- ═══ PUBLICACIONES (Comunidad) ═══
CREATE TABLE public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references auth.users(id) on delete cascade not null,
  body text not null check (char_length(trim(body)) between 5 and 2000),
  topic text not null default 'todos' check (topic in ('todos','startups','hiring','aprendizajes','milestone','pregunta')),
  created_at timestamptz default now()
);

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede leer publicaciones"
  ON public.posts FOR SELECT TO public USING (true);

CREATE POLICY "Publicar como uno mismo"
  ON public.posts FOR INSERT TO public
  WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Solo el autor borra su publicacion"
  ON public.posts FOR DELETE TO public
  USING (auth.uid() = author_id);


-- ═══ OPORTUNIDADES ═══
CREATE TABLE public.opportunities (
  id uuid primary key default gen_random_uuid(),
  author_id uuid references auth.users(id) on delete cascade not null,
  title text not null check (char_length(trim(title)) between 5 and 120),
  description text not null check (char_length(trim(description)) between 10 and 1000),
  type text not null default 'startup' check (type in ('startup','freelance','idea','collab','equity')),
  location text,
  skills text[] default '{}',
  created_at timestamptz default now()
);

ALTER TABLE public.opportunities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede leer oportunidades"
  ON public.opportunities FOR SELECT TO public USING (true);

CREATE POLICY "Publicar oportunidad como uno mismo"
  ON public.opportunities FOR INSERT TO public
  WITH CHECK (auth.uid() = author_id);

CREATE POLICY "Solo el autor borra su oportunidad"
  ON public.opportunities FOR DELETE TO public
  USING (auth.uid() = author_id);


-- ═══ VISITAS AL PERFIL ═══
CREATE TABLE public.profile_views (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references auth.users(id) on delete cascade not null,
  viewer_id uuid references auth.users(id) on delete cascade not null,
  created_at timestamptz default now(),
  constraint no_self_view check (profile_id <> viewer_id)
);

ALTER TABLE public.profile_views ENABLE ROW LEVEL SECURITY;

-- Solo el dueño del perfil puede ver cuantas visitas tiene
CREATE POLICY "Ver mis propias visitas"
  ON public.profile_views FOR SELECT TO public
  USING (auth.uid() = profile_id);

-- Cualquiera autenticado puede registrar que vio un perfil (menos el propio)
CREATE POLICY "Registrar una visita"
  ON public.profile_views FOR INSERT TO public
  WITH CHECK (auth.uid() = viewer_id);
