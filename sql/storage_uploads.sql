-- Bucket de Supabase Storage para fotos de perfil, banners e imagenes de
-- publicaciones. Antes se guardaban como base64 directo en columnas de
-- texto de Postgres (profiles.photo, profiles.banner, posts.image) --
-- eso infla las filas, vuelve lentas las queries que traen perfiles en
-- batch, y nunca se comprime ni cachea como lo haria un CDN real.
--
-- Este archivo solo habilita el bucket hacia adelante: las fotos que ya
-- existen como base64 en la base de datos siguen funcionando exactamente
-- igual (un data: URL es un <img src> valido), no se tocan ni se migran.
-- Solo las subidas NUEVAS despues de este cambio van a Storage.
--
-- Convencion de nombre de archivo: {user_id}/{contexto}-{timestamp}.{ext}
-- El primer segmento del path (el user_id) es lo que las politicas de
-- abajo usan para saber quien es el dueno de cada archivo.
-- Ejecutar completo en Supabase -> SQL Editor -> Run

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('nextwork-uploads', 'nextwork-uploads', true, 5242880, ARRAY['image/png','image/jpeg','image/webp','image/gif'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Cualquiera puede ver los archivos subidos"
  ON storage.objects FOR SELECT TO public
  USING (bucket_id = 'nextwork-uploads');

CREATE POLICY "Subir archivos en mi propia carpeta"
  ON storage.objects FOR INSERT TO public
  WITH CHECK (bucket_id = 'nextwork-uploads' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Reemplazar mis propios archivos"
  ON storage.objects FOR UPDATE TO public
  USING (bucket_id = 'nextwork-uploads' AND auth.uid()::text = (storage.foldername(name))[1])
  WITH CHECK (bucket_id = 'nextwork-uploads' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Borrar mis propios archivos"
  ON storage.objects FOR DELETE TO public
  USING (bucket_id = 'nextwork-uploads' AND auth.uid()::text = (storage.foldername(name))[1]);
