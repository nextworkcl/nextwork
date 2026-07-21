-- Panel de analiticas para founders
-- Ejecutar completo en Supabase -> SQL Editor -> Run
-- (requiere haber corrido antes sql/referrals.sql, usa la columna referred_by)

CREATE OR REPLACE FUNCTION public.get_admin_stats()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE result json;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  SELECT json_build_object(
    'total_profiles', (SELECT count(*) FROM public.profiles),
    'total_posts', (SELECT count(*) FROM public.posts),
    'total_opportunities', (SELECT count(*) FROM public.opportunities),
    'total_applications', (SELECT count(*) FROM public.applications),
    'total_messages', (SELECT count(*) FROM public.messages),
    'connections_accepted', (SELECT count(*) FROM public.connections WHERE status='accepted'),
    'connections_pending', (SELECT count(*) FROM public.connections WHERE status='pending'),
    'connections_declined', (SELECT count(*) FROM public.connections WHERE status='declined'),
    'profiles_with_bio', (SELECT count(*) FROM public.profiles WHERE bio IS NOT NULL AND trim(bio) <> ''),
    'users_with_connection', (SELECT count(DISTINCT p.id) FROM public.profiles p WHERE EXISTS(
      SELECT 1 FROM public.connections c WHERE (c.from_id=p.id OR c.to_id=p.id) AND c.status='accepted'
    )),
    'users_with_message_sent', (SELECT count(DISTINCT sender_id) FROM public.messages),
    'signups_last_30_days', (SELECT coalesce(json_agg(t), '[]'::json) FROM (
      SELECT to_char(date_trunc('day', created_at), 'YYYY-MM-DD') AS day, count(*) AS count
      FROM public.profiles
      WHERE created_at > now() - interval '30 days'
      GROUP BY 1 ORDER BY 1
    ) t),
    'top_referrers', (SELECT coalesce(json_agg(t), '[]'::json) FROM (
      SELECT p.id, p.name, count(r.id) AS referred_count
      FROM public.profiles p
      JOIN public.profiles r ON r.referred_by = p.id
      GROUP BY p.id, p.name
      ORDER BY referred_count DESC
      LIMIT 10
    ) t)
  ) INTO result;

  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_stats() TO authenticated;
