-- Tiempo real en toda la plataforma: notificaciones en vivo, feed en vivo,
-- estado de conexion en vivo, y presencia/lectura en mensajes.
-- Ejecutar completo en Supabase -> SQL Editor -> Run
--
-- 'messages' ya estaba habilitada (sql/messaging.sql). Faltan estas tres
-- tablas para que las nuevas suscripciones (postgres_changes) reciban
-- eventos por Realtime en vez de quedarse esperando en silencio.

ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
ALTER PUBLICATION supabase_realtime ADD TABLE public.posts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.connections;
