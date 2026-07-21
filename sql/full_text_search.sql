-- Busqueda real con Postgres full-text search (reemplaza el matching por
-- substring de los cuadros de busqueda en Buscar y Oportunidades)
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- pg_trgm permite tolerar errores de tipeo (busqueda por similitud de texto),
-- complementando al full-text search normal que solo matchea palabras completas
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- ═══ PERFILES ═══
ALTER TABLE public.profiles ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('spanish', coalesce(name,'')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(role,'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(skills,' '),'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(location,'')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(bio,'')||' '||coalesce(offer,'')||' '||coalesce(vision,'')), 'D')
  ) STORED;

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
ALTER TABLE public.opportunities ADD COLUMN search_vector tsvector
  GENERATED ALWAYS AS (
    setweight(to_tsvector('spanish', coalesce(title,'')), 'A') ||
    setweight(to_tsvector('spanish', coalesce(array_to_string(skills,' '),'')), 'B') ||
    setweight(to_tsvector('spanish', coalesce(location,'')), 'C') ||
    setweight(to_tsvector('spanish', coalesce(description,'')), 'D')
  ) STORED;

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
