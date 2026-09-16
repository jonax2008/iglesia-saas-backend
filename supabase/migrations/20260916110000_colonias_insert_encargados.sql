-- Fase 1: permitir que ministro_en_turno/encargado_estadistica agreguen
-- colonias nuevas al capturar la dirección de una iglesia. La tabla ya
-- tenía lectura abierta y escritura de super_admin desde Fase 0; esto solo
-- añade un permiso adicional de INSERT (no toca update/delete).
create policy colonias_insert_encargados on public.colonias
  for insert to authenticated
  with check (public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica'));
