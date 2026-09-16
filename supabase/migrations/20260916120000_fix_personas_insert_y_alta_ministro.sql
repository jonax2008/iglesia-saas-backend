-- Fase 1 (fix): la política personas_write original exigía que la persona
-- ya fuera ministro de la iglesia del usuario para poder insertarla, lo
-- cual es imposible para una persona nueva (aún no existe el ministro que
-- la referenciaría). Se separa insert/update: el insert se habilita para
-- los roles de gestión de iglesia; el update mantiene el alcance original.
drop policy personas_write on public.personas;

create policy personas_insert on public.personas
  for insert to authenticated
  with check (
    public.rol_actual() in ('super_admin', 'ministro_en_turno', 'encargado_estadistica')
  );

create policy personas_update on public.personas
  for update to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or id = (select persona_id from public.usuarios where id = auth.uid())
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and id in (
        select persona_id from public.ministros where iglesia_id = public.iglesia_actual()
      )
    )
  );

-- Alta atómica de persona + ministro (evita personas huérfanas si el
-- segundo insert falla, ej. por violar una constraint de ministros).
--
-- security definer: un INSERT ... RETURNING de una persona recién creada
-- exige, además de pasar el WITH CHECK de personas_insert, que la fila
-- ya cumpla la política de SELECT (personas_select) — algo imposible para
-- una persona que todavía no tiene ministro que la vincule. Por eso esta
-- función corre como su dueño (bypassa RLS) y hace su propia verificación
-- de permisos, replicando el alcance de ministros_write_admin_o_encargado.
create or replace function public.crear_ministro(
  p_nombres text,
  p_apellido_paterno text,
  p_apellido_materno text,
  p_fecha_nacimiento date,
  p_sexo text,
  p_telefono_celular text,
  p_curp text,
  p_iglesia_id uuid,
  p_correo_institucional text,
  p_fecha_inicio_administracion date,
  p_grado_id uuid,
  p_es_pastor_distrital boolean,
  p_distrito_a_cargo_id uuid,
  p_es_pastor_jurisdiccional boolean,
  p_jurisdiccion_a_cargo_id uuid
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

revoke execute on function public.crear_ministro from public;
grant execute on function public.crear_ministro to authenticated;
