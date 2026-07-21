-- Sistema de invitaciones / referidos
-- Ejecutar completo en Supabase -> SQL Editor -> Run

ALTER TABLE public.profiles ADD COLUMN referral_code text UNIQUE;
ALTER TABLE public.profiles ADD COLUMN referred_by uuid REFERENCES auth.users(id) ON DELETE SET NULL;

-- Genera un codigo unico corto para cada perfil nuevo si no trae uno
CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE new_code text;
BEGIN
  IF NEW.referral_code IS NULL THEN
    LOOP
      new_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 7));
      EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = new_code);
    END LOOP;
    NEW.referral_code := new_code;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_generate_referral_code
  BEFORE INSERT ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.generate_referral_code();

-- Rellena codigo para perfiles que ya existian
UPDATE public.profiles SET referral_code = upper(substr(md5(random()::text || clock_timestamp()::text || id::text), 1, 7))
WHERE referral_code IS NULL;

-- Resuelve un codigo a un id de usuario, publico (se usa antes de iniciar sesion,
-- durante el signup). No expone nada mas que el id
CREATE OR REPLACE FUNCTION public.resolve_referral_code(code text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT id FROM public.profiles WHERE referral_code = upper(code) LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_referral_code(text) TO anon, authenticated;

-- Lista quien se registro con mi codigo (solo campos publicos, no email)
CREATE OR REPLACE FUNCTION public.get_my_referrals()
RETURNS TABLE(id uuid, name text, role text, photo text, color text, created_at timestamptz)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
STABLE
AS $$
  SELECT id, name, role, photo, color, created_at
  FROM public.profiles
  WHERE referred_by = auth.uid()
  ORDER BY created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_referrals() TO authenticated;
