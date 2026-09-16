-- Ajustes de Fase 2 pedidos por el usuario:
-- 1. Iglesia debe estar ligada a un ministro (ministro_actual_id).
-- 2. Ministro que bautizó/testificó pasa a texto libre: muchos no están
--    en el catálogo de ministros (fallecidos, radicando en otro país),
--    y exigir el catálogo bloquearía el registro.

alter table public.iglesias
  add column ministro_actual_id uuid references public.ministros (id) on delete set null;

alter table public.miembros
  add column ministro_bautizo_nombre text,
  add column ministro_testifico_nombre text;

alter table public.miembros
  drop column ministro_bautizo_id,
  drop column ministro_testifico_id;

-- crear_miembro: la firma cambia (uuid -> text para bautizó/testificó),
-- así que se elimina la versión anterior antes de crear la nueva.
drop function if exists public.crear_miembro(
  text, text, text, date, text, text, text, uuid, uuid, text, uuid, date, text,
  uuid, date, uuid, uuid, uuid, uuid, date, uuid[]
);

create or replace function public.crear_miembro(
  p_nombres text,
  p_apellido_paterno text,
  p_apellido_materno text default null,
  p_fecha_nacimiento date default null,
  p_sexo text default null,
  p_telefono_celular text default null,
  p_curp text default null,
  p_iglesia_id uuid default null,
  p_grupo_id uuid default null,
  p_correo_personal text default null,
  p_lugar_nacimiento_ciudad_id uuid default null,
  p_fecha_bautismo date default null,
  p_lugar_bautismo text default null,
  p_ministro_bautizo_nombre text default null,
  p_fecha_espiritu_santo date default null,
  p_ministro_testifico_nombre text default null,
  p_nivel_estudios_id uuid default null,
  p_profesion_ocupacion_id uuid default null,
  p_estado_civil_id uuid default null,
  p_credencial_vigente_hasta date default null,
  p_comision_ids uuid[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona_id uuid;
  v_miembro_id uuid;
  v_comision_id uuid;
begin
  if not (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and p_iglesia_id = public.iglesia_actual()
    )
  ) then
    raise exception 'No tienes permiso para registrar miembros en esta iglesia';
  end if;

  insert into public.personas (
    nombres, apellido_paterno, apellido_materno, fecha_nacimiento, sexo,
    telefono_celular, curp
  )
  values (
    p_nombres, p_apellido_paterno, p_apellido_materno, p_fecha_nacimiento,
    p_sexo, p_telefono_celular, p_curp
  )
  returning id into v_persona_id;

  insert into public.miembros (
    persona_id, iglesia_id, grupo_id, correo_personal,
    lugar_nacimiento_ciudad_id, fecha_bautismo, lugar_bautismo,
    ministro_bautizo_nombre, fecha_espiritu_santo, ministro_testifico_nombre,
    nivel_estudios_id, profesion_ocupacion_id, estado_civil_id,
    credencial_vigente_hasta
  )
  values (
    v_persona_id, p_iglesia_id, p_grupo_id, p_correo_personal,
    p_lugar_nacimiento_ciudad_id, p_fecha_bautismo, p_lugar_bautismo,
    p_ministro_bautizo_nombre, p_fecha_espiritu_santo, p_ministro_testifico_nombre,
    p_nivel_estudios_id, p_profesion_ocupacion_id, p_estado_civil_id,
    p_credencial_vigente_hasta
  )
  returning id into v_miembro_id;

  if p_comision_ids is not null then
    foreach v_comision_id in array p_comision_ids loop
      insert into public.miembro_comisiones (miembro_id, comision_id)
      values (v_miembro_id, v_comision_id);
    end loop;
  end if;

  return v_miembro_id;
end;
$$;

revoke execute on function public.crear_miembro from public;
grant execute on function public.crear_miembro to authenticated;

-- Corrección de un hueco de RLS: personas_select/personas_update solo
-- consideraban el vínculo vía ministros, así que el staff de la iglesia
-- no podía ver ni editar los datos personales de sus propios miembros
-- (necesario para las pantallas de detalle/edición). Se agrega el
-- vínculo vía miembros, y de paso el de encargados/auxiliares de grupo
-- (lo van a necesitar en Fase 3 para asistencia).
drop policy personas_select on public.personas;
drop policy personas_update on public.personas;

create policy personas_select on public.personas
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or id = (select persona_id from public.usuarios where id = auth.uid())
    or id in (
      select persona_id from public.ministros where iglesia_id = public.iglesia_actual()
    )
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and id in (
        select persona_id from public.miembros where iglesia_id = public.iglesia_actual()
      )
    )
    or (
      public.rol_actual() in ('encargado_grupo', 'auxiliar_grupo')
      and id in (
        select persona_id from public.miembros m where public.es_encargado_de_grupo(m.grupo_id)
      )
    )
  );

create policy personas_update on public.personas
  for update to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or id = (select persona_id from public.usuarios where id = auth.uid())
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and (
        id in (select persona_id from public.ministros where iglesia_id = public.iglesia_actual())
        or id in (select persona_id from public.miembros where iglesia_id = public.iglesia_actual())
      )
    )
  );
