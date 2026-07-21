-- Organizaciones / equipos (startups como entidad propia, no solo personas)
-- Ejecutar completo en Supabase -> SQL Editor -> Run

CREATE TABLE public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 2 and 100),
  description text check (char_length(trim(description)) <= 1000),
  logo text,
  website text,
  location text,
  created_by uuid references auth.users(id) on delete cascade not null,
  created_at timestamptz default now()
);

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede ver organizaciones"
  ON public.organizations FOR SELECT TO public USING (true);

CREATE POLICY "Crear organizacion como uno mismo"
  ON public.organizations FOR INSERT TO public
  WITH CHECK (auth.uid() = created_by);


CREATE TABLE public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade not null,
  user_id uuid references auth.users(id) on delete cascade not null,
  role text not null default 'member' check (role in ('admin','member')),
  joined_at timestamptz default now(),
  unique(organization_id, user_id)
);

ALTER TABLE public.organization_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Cualquiera puede ver miembros de organizaciones"
  ON public.organization_members FOR SELECT TO public USING (true);

CREATE POLICY "Admins agregan miembros"
  ON public.organization_members FOR INSERT TO public
  WITH CHECK (
    EXISTS(SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_members.organization_id
        AND om.user_id = auth.uid() AND om.role = 'admin')
  );

CREATE POLICY "Admins quitan miembros o uno se va solo"
  ON public.organization_members FOR DELETE TO public
  USING (
    auth.uid() = user_id
    OR EXISTS(SELECT 1 FROM public.organization_members om
      WHERE om.organization_id = organization_members.organization_id
        AND om.user_id = auth.uid() AND om.role = 'admin')
  );

-- Ahora que existe organization_members, se pueden agregar las policies de
-- organizations que dependen de ella (editar/eliminar solo admins)
CREATE POLICY "Admins de la organizacion la editan"
  ON public.organizations FOR UPDATE TO public
  USING (EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id = id AND user_id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id = id AND user_id = auth.uid() AND role = 'admin'));

CREATE POLICY "Admins de la organizacion la eliminan"
  ON public.organizations FOR DELETE TO public
  USING (EXISTS(SELECT 1 FROM public.organization_members WHERE organization_id = id AND user_id = auth.uid() AND role = 'admin'));

-- El creador queda como admin automaticamente (evita el problema de "huevo
-- y gallina": la policy de INSERT en organization_members exige ya ser
-- admin, asi que la primera fila se crea por trigger con permisos propios)
CREATE OR REPLACE FUNCTION public.add_org_creator_as_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO public.organization_members (organization_id, user_id, role)
  VALUES (NEW.id, NEW.created_by, 'admin');
  RETURN NEW;
END;
$$;

CREATE TRIGGER organizations_add_creator
  AFTER INSERT ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.add_org_creator_as_admin();

-- Evita que la organizacion se quede sin ningun administrador
CREATE OR REPLACE FUNCTION public.check_not_last_org_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.role = 'admin' THEN
    IF (SELECT count(*) FROM public.organization_members WHERE organization_id = OLD.organization_id AND role = 'admin') <= 1 THEN
      RAISE EXCEPTION 'La organización debe tener al menos un administrador.';
    END IF;
  END IF;
  RETURN OLD;
END;
$$;

CREATE TRIGGER organization_members_check_last_admin
  BEFORE DELETE ON public.organization_members
  FOR EACH ROW EXECUTE FUNCTION public.check_not_last_org_admin();

-- Limite anti-spam
CREATE OR REPLACE FUNCTION public.check_org_rate_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF (SELECT count(*) FROM public.organizations WHERE created_by = NEW.created_by AND created_at > now() - interval '1 day') >= 5 THEN
    RAISE EXCEPTION 'Has creado muchas organizaciones hoy. Intenta más tarde.';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER organizations_rate_limit
  BEFORE INSERT ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION public.check_org_rate_limit();


-- ═══ OPORTUNIDADES A NOMBRE DE UNA ORGANIZACION ═══
ALTER TABLE public.opportunities ADD COLUMN organization_id uuid REFERENCES public.organizations(id) ON DELETE SET NULL;

-- Solo se puede atribuir una oportunidad a una organizacion de la que
-- realmente eres miembro (author_id sigue siendo quien la publica, para
-- mantener la trazabilidad y el limite anti-spam de siempre)
CREATE OR REPLACE FUNCTION public.check_org_membership_for_opportunity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.organization_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.organization_members WHERE organization_id = NEW.organization_id AND user_id = NEW.author_id) THEN
      RAISE EXCEPTION 'No perteneces a esta organización.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER opportunities_check_org
  BEFORE INSERT OR UPDATE ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.check_org_membership_for_opportunity();
