-- Perfiles verificados
-- Ejecutar completo en Supabase -> SQL Editor -> Run

ALTER TABLE public.profiles ADD COLUMN verified boolean NOT NULL DEFAULT false;

-- Mismo patron que is_admin: nadie puede auto-verificarse desde el navegador.
-- Solo se cambia via la funcion set_profile_verified (solo admins) o a mano
-- desde el Table Editor.
REVOKE UPDATE (verified) ON public.profiles FROM authenticated, anon;

CREATE OR REPLACE FUNCTION public.set_profile_verified(target_id uuid, value boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;
  UPDATE public.profiles SET verified = value WHERE id = target_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_profile_verified(uuid, boolean) TO authenticated;

-- Expone "verified" en la vista publica. Reconstruida con exactamente las
-- mismas columnas que tenia antes (verificado contra produccion) + verified.
CREATE OR REPLACE VIEW public.perfiles_publicos AS
SELECT id, name, role, location, bio, color, exp, skills, hobbies, offer,
       collab, availability, vision, photo, banner, status, link, verified
FROM public.profiles;
