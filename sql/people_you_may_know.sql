-- "Personas que quizas conozcas" -- sugerencias de conexion basadas en el
-- grafo de conexiones (2do grado: gente conectada con tus conexiones) con
-- respaldo por habilidades compartidas. Sin IA/embeddings a proposito.
-- Ejecutar completo en Supabase -> SQL Editor -> Run

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
  my_skills AS (
    SELECT unnest(skills) AS skill FROM public.profiles WHERE id = auth.uid()
  ),
  skill_matches AS (
    SELECT p.id AS candidate_id
    FROM public.profiles p
    JOIN my_skills ms ON ms.skill = ANY(p.skills)
    WHERE p.id NOT IN (SELECT id FROM excluded)
      AND p.id NOT IN (SELECT candidate_id FROM ranked_mutual)
    GROUP BY p.id
  ),
  combined AS (
    SELECT candidate_id, mutual_count FROM ranked_mutual
    UNION ALL
    SELECT candidate_id, 0 FROM skill_matches
  )
  SELECT p.id, p.name, p.role, p.photo, p.color,
    coalesce(combined.mutual_count, 0) AS mutual_count,
    CASE WHEN combined.mutual_count > 0 THEN 'mutual' ELSE 'skills' END AS reason
  FROM combined
  JOIN public.profiles p ON p.id = combined.candidate_id
  WHERE NOT public.is_blocked_between(auth.uid(), combined.candidate_id)
  ORDER BY mutual_count DESC
  LIMIT limit_count;
$$;

GRANT EXECUTE ON FUNCTION public.get_people_you_may_know(int) TO authenticated;
