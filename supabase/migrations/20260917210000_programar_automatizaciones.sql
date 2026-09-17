-- Programa las automatizaciones de Fase 4 para correr solas todos los
-- días vía pg_cron (sin esto, alguien tendría que dispararlas a mano).
create extension if not exists pg_cron with schema extensions;

select cron.schedule(
  'actualizar-categorias-miembros-diario',
  '0 7 * * *',
  $$select public.actualizar_categorias_miembros();$$
);

select cron.schedule(
  'generar-avisos-cambio-grupo-diario',
  '15 7 * * *',
  $$select public.generar_avisos_cambio_grupo();$$
);
