-- Eventos: presenciales, online o hibridos, opcionalmente ligados a un
-- grupo/comunidad. Se pueden filtrar por ciudad, pais y comunidad.
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.events (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid references auth.users(id) on delete cascade not null,
  group_id uuid references public.groups(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 3 and 120),
  description text not null default '' check (char_length(description) <= 1000),
  city text not null default '' check (char_length(city) <= 80),
  country text not null default '' check (char_length(country) <= 80),
  location_type text not null default 'presencial' check (location_type in ('presencial','online','hibrido')),
  location_detail text not null default '' check (char_length(location_detail) <= 200),
  starts_at timestamptz not null,
  ends_at timestamptz,
  cover_color text not null default '#2d6b4a',
  created_at timestamptz default now(),
  constraint events_dates_ok check (ends_at is null or ends_at >= starts_at)
);

CREATE INDEX idx_events_group_id ON public.events(group_id);
CREATE INDEX idx_events_starts_at ON public.events(starts_at);

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;

-- Mismo criterio de visibilidad que los posts de grupo: un evento sin
-- grupo es publico, un evento de grupo publico es publico, un evento de
-- grupo privado solo lo ven sus miembros aprobados
CREATE POLICY "Leer eventos segun visibilidad"
  ON public.events FOR SELECT TO public
  USING (
    group_id IS NULL
    OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = events.group_id AND g.is_private = false)
    OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = events.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved')
  );

CREATE POLICY "Crear evento como uno mismo"
  ON public.events FOR INSERT TO public
  WITH CHECK (
    auth.uid() = creator_id
    AND (group_id IS NULL OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = events.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved'))
  );

CREATE POLICY "Autor edita su evento"
  ON public.events FOR UPDATE TO public
  USING (auth.uid() = creator_id)
  WITH CHECK (auth.uid() = creator_id);

CREATE POLICY "Autor o admin del grupo borra el evento"
  ON public.events FOR DELETE TO public
  USING (
    auth.uid() = creator_id
    OR (group_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = events.group_id AND gm.user_id = auth.uid() AND gm.role = 'admin' AND gm.status = 'approved'))
  );


-- ═══ RSVP ═══
CREATE TABLE public.event_rsvps (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references public.events(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  status text not null check (status in ('going','interested')),
  created_at timestamptz default now(),
  unique (event_id, user_id)
);

CREATE INDEX idx_event_rsvps_event_id ON public.event_rsvps(event_id);
CREATE INDEX idx_event_rsvps_user_id ON public.event_rsvps(user_id);

ALTER TABLE public.event_rsvps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Ver rsvps de eventos visibles"
  ON public.event_rsvps FOR SELECT TO public
  USING (
    EXISTS (
      SELECT 1 FROM public.events e
      WHERE e.id = event_rsvps.event_id
      AND (
        e.group_id IS NULL
        OR EXISTS (SELECT 1 FROM public.groups g WHERE g.id = e.group_id AND g.is_private = false)
        OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = e.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved')
      )
    )
  );

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
        OR EXISTS (SELECT 1 FROM public.group_members gm WHERE gm.group_id = e.group_id AND gm.user_id = auth.uid() AND gm.status = 'approved')
      )
    )
  );

CREATE POLICY "Cambiar mi propio RSVP"
  ON public.event_rsvps FOR UPDATE TO public
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Quitar mi propio RSVP"
  ON public.event_rsvps FOR DELETE TO public
  USING (user_id = auth.uid());


-- ═══ REALTIME ═══
ALTER PUBLICATION supabase_realtime ADD TABLE public.events;
ALTER PUBLICATION supabase_realtime ADD TABLE public.event_rsvps;
