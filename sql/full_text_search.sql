-- Busqueda real con Postgres full-text search (reemplaza el matching por
-- substring de los cuadros de busqueda en Buscar y Oportunidades)
-- Ejecutar completo en Supabase -> SQL Editor -> Run
--
-- Nota: search_vector NO es una columna GENERATED (Postgres no permite
-- to_tsvector() ahi porque considera la configuracion de idioma "no
-- inmutable" -- error 42P17). En su lugar se mantiene con un trigger,
-- que es el patron estandar de Postgres para full-text search.

-- pg_trgm permite tolerar errores de tipeo (busqueda por similitud de texto),
-- complementando al full-text search normal que solo matchea palabras completas
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ═══ PERFILES ═══
ALTER TABLE public.profiles ADD COLUMN search_vector tsvector;

CREATE OR REPLACE FUNCTION public.profiles_search_vector_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('spanish', coalesce(NEW.name,'')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(NEW.role,'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(NEW.skills,' '),'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(NEW.location,'')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(NEW.bio,'')||' '||coalesce(NEW.offer,'')||' '||coalesce(NEW.vision,'')), 'D');
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_search_vector_trigger
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_search_vector_update();

-- Rellena el vector de busqueda para los perfiles que ya existian
UPDATE public.profiles SET search_vector =
  setweight(to_tsvector('spanish', coalesce(name,'')), 'A') ||
  setweight(to_tsvector('spanish', coalesce(role,'')), 'B') ||
  setweight(to_tsvector('spanish', coalesce(array_to_string(skills,' '),'')), 'B') ||
  setweight(to_tsvector('spanish', coalesce(location,'')), 'C') ||
  setweight(to_tsvector('spanish', coalesce(bio,'')||' '||coalesce(offer,'')||' '||coalesce(vision,'')), 'D');

CREATE INDEX profiles_search_idx ON public.profiles USING gin(search_vector);
CREATE INDEX profiles_name_trgm_idx ON public.profiles USING gin(name gin_trgm_ops);

-- Devuelve solo las columnas publicas (nunca el email), igual que la vista
-- perfiles_publicos, pero permite buscar porque corre con permisos propios
-- (SECURITY DEFINER) sobre la tabla real donde vive el search_vector
CREATE OR REPLACE FUNCTION public.search_profiles(query text)
RETURNS TABLE(id uuid, name text, role text, bio text, offer text, vision text, location text, skills text[], color text, photo text, banner text, rank real)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT p.id, p.name, p.role, p.bio, p.offer, p.vision, p.location, p.skills, p.color, p.photo, p.banner,
    ts_rank(p.search_vector, websearch_to_tsquery('spanish', query)) AS rank
  FROM public.profiles p
  WHERE p.search_vector @@ websearch_to_tsquery('spanish', query)
     OR p.name % query
  ORDER BY rank DESC, similarity(p.name, query) DESC
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION public.search_profiles(text) TO anon, authenticated;


-- ═══ OPORTUNIDADES ═══
ALTER TABLE public.opportunities ADD COLUMN search_vector tsvector;

CREATE OR REPLACE FUNCTION public.opportunities_search_vector_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.search_vector :=
    setweight(to_tsvector('spanish', coalesce(NEW.title,'')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(NEW.skills,' '),'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(NEW.location,'')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(NEW.description,'')), 'D');
  RETURN NEW;
END;
$$;

CREATE TRIGGER opportunities_search_vector_trigger
  BEFORE INSERT OR UPDATE ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.opportunities_search_vector_update();

-- Rellena el vector de busqueda para las oportunidades que ya existian
UPDATE public.opportunities SET search_vector =
  setweight(to_tsvector('spanish', coalesce(title,'')), 'A') ||
  setweight(to_tsvector('spanish', coalesce(array_to_string(skills,' '),'')), 'B') ||
  setweight(to_tsvector('spanish', coalesce(location,'')), 'C') ||
  setweight(to_tsvector('spanish', coalesce(description,'')), 'D');

CREATE INDEX opportunities_search_idx ON public.opportunities USING gin(search_vector);

CREATE OR REPLACE FUNCTION public.search_opportunities(query text)
RETURNS TABLE(id uuid, author_id uuid, title text, description text, type text, location text, skills text[], created_at timestamptz, rank real)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT o.id, o.author_id, o.title, o.description, o.type, o.location, o.skills, o.created_at,
    ts_rank(o.search_vector, websearch_to_tsquery('spanish', query)) AS rank
  FROM public.opportunities o
  WHERE o.search_vector @@ websearch_to_tsquery('spanish', query)
     OR o.title % query
  ORDER BY rank DESC, o.created_at DESC
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION public.search_opportunities(text) TO anon, authenticated;
