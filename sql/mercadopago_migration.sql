-- Cambia el proveedor de pago de Stripe a MercadoPago (Stripe no soporta
-- cuentas de negocio registradas en Chile). Correr DESPUES de
-- sql/monetizacion_pro.sql, que ya se ejecuto.
-- Ejecutar completo en Supabase -> SQL Editor -> Run

-- stripe_customer_id nunca llego a usarse (no se desplego Stripe)
ALTER TABLE public.profiles DROP COLUMN IF EXISTS stripe_customer_id;

ALTER TABLE public.profiles ADD COLUMN mercadopago_subscription_id text;

-- Mismo patron que is_admin/verified/pro_active: solo el webhook de
-- MercadoPago (via service role key) puede tocar esta columna
REVOKE UPDATE (mercadopago_subscription_id) ON public.profiles FROM authenticated, anon;
