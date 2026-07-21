-- Universidad/empresa en el perfil + usarlos como señal en
-- "Personas que quizas conozcas"
-- Ejecutar completo en Supabase -> SQL Editor -> Run

ALTER TABLE public.profiles ADD COLUMN university text;
ALTER TABLE public.profiles ADD COLUMN company text;

-- Se agregan a la vista publica (mismo patron usado para "verified"/"pro_active":
-- reconstruida con exactamente las columnas que ya tenia + las nuevas)
CREATE OR REPLACE VIEW public.perfiles_publicos AS
SELECT id, name, role, location, bio, color, exp, skills, hobbies, offer,
       collab, availability, vision, photo, banner, status, link, verified,
       pro_active, university, company
FROM public.profiles;

-- Reemplaza get_people_you_may_know: ahora prioriza conexiones en comun,
-- despues habilidades compartidas, y como ultimo respaldo universidad o
-- empresa en comun (en ese orden, sin duplicar a nadie entre categorias)
CREATE OR REPLACE FUNCTION public.get_people_you_may_know(limit_count int DEFAULT 10)
RETURNS TABLE(id uuid, name text, role text, photo text, color text, mutual_count bigint, reason text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  WITH my_connections AS (
    SELECT CASE WHEN from_id = auth.uid() THEN to_id ELSE from_id END AS friend_id
    FROM public.connections
    WHERE status = 'accepted' AND (from_id = auth.uid() OR to_id = auth.uid())
  ),
  excluded AS (
    SELECT friend_id AS id FROM my_connections
    UNION
    SELECT auth.uid()
    UNION
    SELECT CASE WHEN from_id = auth.uid() THEN to_id ELSE from_id END
    FROM public.connections
    WHERE status IN ('pending','declined') AND (from_id = auth.uid() OR to_id = auth.uid())
  ),
  second_degree AS (
    SELECT CASE WHEN c.from_id = mc.friend_id THEN c.to_id ELSE c.from_id END AS candidate_id,
           mc.friend_id
    FROM public.connections c
    JOIN my_connections mc ON (c.from_id = mc.friend_id OR c.to_id = mc.friend_id)
    WHERE c.status = 'accepted'
  ),
  ranked_mutual AS (
    SELECT candidate_id, count(DISTINCT friend_id) AS mutual_count
    FROM second_degree
    WHERE candidate_id NOT IN (SELECT id FROM excluded)
    GROUP BY candidate_id
  ),
  me AS (
    SELECT skills, university, company FROM public.profiles WHERE id = auth.uid()
  ),
  my_skills AS (
    SELECT unnest(skills) AS skill FROM me
  ),
  skill_matches AS (
    SELECT p.id AS candidate_id
    FROM public.profiles p
    JOIN my_skills ms ON ms.skill = ANY(p.skills)
    WHERE p.id NOT IN (SELECT id FROM excluded)
      AND p.id NOT IN (SELECT candidate_id FROM ranked_mutual)
    GROUP BY p.id
  ),
  university_matches AS (
    SELECT p.id AS candidate_id
    FROM public.profiles p, me
    WHERE me.university IS NOT NULL AND trim(me.university) <> ''
      AND lower(trim(p.university)) = lower(trim(me.university))
      AND p.id NOT IN (SELECT id FROM excluded)
      AND p.id NOT IN (SELECT candidate_id FROM ranked_mutual)
      AND p.id NOT IN (SELECT candidate_id FROM skill_matches)
  ),
  company_matches AS (
    SELECT p.id AS candidate_id
    FROM public.profiles p, me
    WHERE me.company IS NOT NULL AND trim(me.company) <> ''
      AND lower(trim(p.company)) = lower(trim(me.company))
      AND p.id NOT IN (SELECT id FROM excluded)
      AND p.id NOT IN (SELECT candidate_id FROM ranked_mutual)
      AND p.id NOT IN (SELECT candidate_id FROM skill_matches)
      AND p.id NOT IN (SELECT candidate_id FROM university_matches)
  ),
  combined AS (
    SELECT candidate_id, mutual_count, 'mutual' AS reason FROM ranked_mutual
    UNION ALL
    SELECT candidate_id, 0, 'skills' FROM skill_matches
    UNION ALL
    SELECT candidate_id, 0, 'university' FROM university_matches
    UNION ALL
    SELECT candidate_id, 0, 'company' FROM company_matches
  )
  SELECT p.id, p.name, p.role, p.photo, p.color,
    combined.mutual_count,
    combined.reason
  FROM combined
  JOIN public.profiles p ON p.id = combined.candidate_id
  WHERE NOT public.is_blocked_between(auth.uid(), combined.candidate_id)
  ORDER BY combined.mutual_count DESC
  LIMIT limit_count;
$$;
