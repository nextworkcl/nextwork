-- Sistema de solicitudes de conexion entre usuarios
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.connections (
  id uuid primary key default gen_random_uuid(),
  from_id uuid references auth.users(id) on delete cascade not null,
  to_id uuid references auth.users(id) on delete cascade not null,
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz default now(),
  responded_at timestamptz,
  constraint no_self_connect check (from_id <> to_id),
  unique(from_id, to_id)
);

ALTER TABLE public.connections ENABLE ROW LEVEL SECURITY;

-- Solo puedo ver conexiones donde soy emisor o receptor
CREATE POLICY "Ver mis conexiones"
  ON public.connections FOR SELECT TO public
  USING (auth.uid() = from_id OR auth.uid() = to_id);

-- Solo puedo crear una solicitud como emisor de mi propia cuenta
CREATE POLICY "Enviar solicitud propia"
  ON public.connections FOR INSERT TO public
  WITH CHECK (auth.uid() = from_id);

-- Solo el receptor puede aceptar/rechazar
CREATE POLICY "Receptor responde solicitud"
  ON public.connections FOR UPDATE TO public
  USING (auth.uid() = to_id)
  WITH CHECK (auth.uid() = to_id);

-- Solo el emisor puede cancelar su propia solicitud
CREATE POLICY "Emisor puede cancelar su solicitud"
  ON public.connections FOR DELETE TO public
  USING (auth.uid() = from_id);

-- Puedo ver el perfil COMPLETO (incluye email) de alguien con quien
-- tengo una conexion aceptada -- asi se comparte el contacto real
-- solo cuando ambas partes aceptaron conectar
CREATE POLICY "Ver perfil de conexiones aceptadas"
  ON public.profiles FOR SELECT TO public
  USING (
    EXISTS (
      SELECT 1 FROM public.connections c
      WHERE c.status = 'accepted'
        AND ((c.from_id = auth.uid() AND c.to_id = profiles.id)
          OR (c.to_id = auth.uid() AND c.from_id = profiles.id))
    )
  );
