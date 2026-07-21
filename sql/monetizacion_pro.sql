-- Monetizacion: plan Nextwork Pro (Stripe)
-- Ejecutar completo en Supabase -> SQL Editor -> Run
--
-- Esta parte NO empieza a cobrar nada por si sola: solo prepara la base
-- de datos. El pago de verdad requiere desplegar las Edge Functions en
-- supabase/functions/ (ver instrucciones en cada archivo) y crear una
-- cuenta de Stripe con el plan mensual "Nextwork Pro".

ALTER TABLE public.profiles ADD COLUMN stripe_customer_id text;
ALTER TABLE public.profiles ADD COLUMN pro_active boolean NOT NULL DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN pro_current_period_end timestamptz;

-- Mismo patron que is_admin/verified: solo el webhook de Stripe (que usa
-- la service role key, no sujeta a este REVOKE) puede tocar estas columnas
REVOKE UPDATE (stripe_customer_id, pro_active, pro_current_period_end)
  ON public.profiles FROM authenticated, anon;

-- Beneficio Pro #1: destacar una oportunidad (aparece primero y con badge)
ALTER TABLE public.opportunities ADD COLUMN is_featured boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.check_featured_requires_pro()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.is_featured THEN
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.author_id AND pro_active = true) THEN
      RAISE EXCEPTION 'Necesitas Nextwork Pro para destacar una oportunidad.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER opportunities_check_featured
  BEFORE INSERT OR UPDATE ON public.opportunities
  FOR EACH ROW EXECUTE FUNCTION public.check_featured_requires_pro();

-- Expone pro_active en la vista publica (para mostrar el badge PRO), misma
-- reconstruccion segura que se uso para agregar "verified"
CREATE OR REPLACE VIEW public.perfiles_publicos AS
SELECT id, name, role, location, bio, color, exp, skills, hobbies, offer,
       collab, availability, vision, photo, banner, status, link, verified, pro_active
FROM public.profiles;
