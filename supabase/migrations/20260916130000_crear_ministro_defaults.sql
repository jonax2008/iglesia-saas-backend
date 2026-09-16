-- Marca como opcionales (default null) los parámetros de crear_ministro
-- que son legítimamente opcionales, para que el codegen de tipos de
-- Supabase los tipifique como nullable en el frontend.
create or replace function public.crear_ministro(
  p_nombres text,
  p_apellido_paterno text,
  p_apellido_materno text default null,
  p_fecha_nacimiento date default null,
  p_sexo text default null,
  p_telefono_celular text default null,
  p_curp text default null,
  p_iglesia_id uuid default null,
  p_correo_institucional text default null,
  p_fecha_inicio_administracion date default null,
  p_grado_id uuid default null,
  p_es_pastor_distrital boolean default false,
  p_distrito_a_cargo_id uuid default null,
  p_es_pastor_jurisdiccional boolean default false,
  p_jurisdiccion_a_cargo_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_persona_id uuid;
  v_ministro_id uuid;
begin
  if not (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and p_iglesia_id = public.iglesia_actual()
    )
  ) then
    raise exception 'No tienes permiso para crear ministros en esta iglesia';
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

  insert into public.ministros (
    persona_id, iglesia_id, correo_institucional, fecha_inicio_administracion,
    grado_id, es_pastor_distrital, distrito_a_cargo_id, es_pastor_jurisdiccional,
    jurisdiccion_a_cargo_id
  )
  values (
    v_persona_id, p_iglesia_id, p_correo_institucional, p_fecha_inicio_administracion,
    p_grado_id, p_es_pastor_distrital, p_distrito_a_cargo_id, p_es_pastor_jurisdiccional,
    p_jurisdiccion_a_cargo_id
  )
  returning id into v_ministro_id;

  return v_ministro_id;
end;
$$;
