-- Me gusta reales en publicaciones
-- Ejecutar en Supabase -> SQL Editor -> Run

CREATE TABLE public.post_likes (
  post_id uuid references public.posts(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede ver los likes"
  ON public.post_likes FOR SELECT TO public USING (true);

CREATE POLICY "Dar like como uno mismo"
  ON public.post_likes FOR INSERT TO public
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Quitar mi propio like"
  ON public.post_likes FOR DELETE TO public
  USING (auth.uid() = user_id);
