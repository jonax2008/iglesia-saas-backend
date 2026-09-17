-- Pulido de seguridad: grados_ministros, comisiones, niveles_estudio,
-- estados_civiles y profesiones_ocupaciones solo permitían escritura a
-- super_admin (heredado del bloque genérico de Fase 0), pero sus
-- pantallas de CRUD ya están expuestas a ministro_en_turno y
-- encargado_estadistica (NAV_ADMIN del frontend). Son catálogos
-- compartidos de toda la organización (no dependen de una sola iglesia),
-- así que se amplía el permiso de escritura a esos dos roles también.
do $$
declare
  t text;
begin
  foreach t in array array[
    'grados_ministros', 'comisiones', 'niveles_estudio', 'estados_civiles',
    'profesiones_ocupaciones'
  ]
  loop
    execute format(
      'create policy %I_write_encargados on public.%I for all to authenticated using (public.rol_actual() in (%L, %L)) with check (public.rol_actual() in (%L, %L));',
      t, t, 'ministro_en_turno', 'encargado_estadistica', 'ministro_en_turno', 'encargado_estadistica'
    );
  end loop;
end $$;
