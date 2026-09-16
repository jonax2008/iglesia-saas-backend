-- Fase 2: miembros, grupos y familias
-- Ver Documents/personal/iglesia-saas/PLAN.md secciones 5.2, 5.3

-- =========================================================================
-- Miembros y grupos tienen una referencia circular (miembros.grupo_id ->
-- grupos.id, grupos.encargado_miembro_id -> miembros.id), así que se crean
-- las columnas primero sin FK y se agregan las constraints al final.
-- =========================================================================
create table public.miembros (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null unique references public.personas (id),
  iglesia_id uuid not null references public.iglesias (id),
  grupo_id uuid not null,
  correo_personal text,
  lugar_nacimiento_ciudad_id uuid references public.ciudades (id),
  lugar_nacimiento_estado_id uuid references public.estados (id),
  lugar_nacimiento_pais_id uuid references public.paises (id),
  fecha_bautismo date not null,
  lugar_bautismo text,
  ministro_bautizo_id uuid references public.ministros (id),
  fecha_espiritu_santo date not null,
  ministro_testifico_id uuid references public.ministros (id),
  nivel_estudios_id uuid references public.niveles_estudio (id),
  profesion_ocupacion_id uuid references public.profesiones_ocupaciones (id),
  categoria text not null default 'activo'
    check (categoria in ('activo', 'retirado_temporal', 'archivo')),
  estado_civil_id uuid references public.estados_civiles (id),
  credencial_vigente_hasta date,
  creado_en timestamptz not null default now()
);
create index miembros_iglesia_id_idx on public.miembros (iglesia_id);
create index miembros_grupo_id_idx on public.miembros (grupo_id);

create table public.grupos (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias (id),
  nombre text not null,
  encargado_miembro_id uuid references public.miembros (id),
  edad_inicial int not null,
  edad_final int not null,
  creado_en timestamptz not null default now(),
  constraint grupos_edad_check check (edad_inicial <= edad_final)
);
create index grupos_iglesia_id_idx on public.grupos (iglesia_id);

alter table public.miembros
  add constraint miembros_grupo_id_fkey foreign key (grupo_id) references public.grupos (id);

-- Deriva lugar_nacimiento_estado_id/pais_id desde la ciudad, igual que en
-- iglesias, para no pedir tres selects redundantes ni permitir inconsistencias.
create or replace function public.miembros_derivar_lugar_nacimiento()
returns trigger
language plpgsql
as $$
begin
  if new.lugar_nacimiento_ciudad_id is null then
    new.lugar_nacimiento_estado_id := null;
    new.lugar_nacimiento_pais_id := null;
    return new;
  end if;

  select c.estado_id, e.pais_id
  into strict new.lugar_nacimiento_estado_id, new.lugar_nacimiento_pais_id
  from public.ciudades c
  join public.estados e on e.id = c.estado_id
  where c.id = new.lugar_nacimiento_ciudad_id;
  return new;
end;
$$;

create trigger miembros_sync_lugar_nacimiento
  before insert or update of lugar_nacimiento_ciudad_id on public.miembros
  for each row execute function public.miembros_derivar_lugar_nacimiento();

-- =========================================================================
-- Auxiliares de grupo (máx. 2 por grupo) y límite de liderazgo (un miembro
-- puede ser encargado y/o auxiliar de hasta 3 grupos en total)
-- =========================================================================
create table public.grupo_auxiliares (
  grupo_id uuid not null references public.grupos (id) on delete cascade,
  miembro_id uuid not null references public.miembros (id),
  primary key (grupo_id, miembro_id)
);

create or replace function public.grupo_auxiliares_check_max()
returns trigger
language plpgsql
as $$
begin
  if (select count(*) from public.grupo_auxiliares where grupo_id = new.grupo_id) >= 2 then
    raise exception 'Un grupo no puede tener más de 2 auxiliares';
  end if;
  return new;
end;
$$;

create trigger grupo_auxiliares_max
  before insert on public.grupo_auxiliares
  for each row execute function public.grupo_auxiliares_check_max();

-- NOTA: no se puede compartir una sola función de trigger entre grupos y
-- grupo_auxiliares referenciando NEW.encargado_miembro_id / NEW.miembro_id
-- indistintamente: PL/pgSQL resuelve los campos de NEW contra el tipo de
-- fila real de la tabla que dispara el trigger, y falla en tiempo de
-- ejecución si esa columna no existe en esa tabla. Se usan dos funciones.
create or replace function public.contar_grupos_liderados(p_miembro_id uuid)
returns int
language sql
stable
as $$
  select
    (select count(*) from public.grupos where encargado_miembro_id = p_miembro_id)
    + (select count(*) from public.grupo_auxiliares where miembro_id = p_miembro_id);
$$;

create or replace function public.grupos_check_max_liderazgo()
returns trigger
language plpgsql
as $$
begin
  if public.contar_grupos_liderados(new.encargado_miembro_id) >= 3 then
    raise exception 'Este miembro ya está a cargo del máximo de 3 grupos (como encargado o auxiliar)';
  end if;
  return new;
end;
$$;

create trigger grupos_max_liderazgo
  before insert or update of encargado_miembro_id on public.grupos
  for each row
  when (new.encargado_miembro_id is not null)
  execute function public.grupos_check_max_liderazgo();

create or replace function public.grupo_auxiliares_check_max_liderazgo()
returns trigger
language plpgsql
as $$
begin
  if public.contar_grupos_liderados(new.miembro_id) >= 3 then
    raise exception 'Este miembro ya está a cargo del máximo de 3 grupos (como encargado o auxiliar)';
  end if;
  return new;
end;
$$;

create trigger grupo_auxiliares_max_liderazgo
  before insert on public.grupo_auxiliares
  for each row execute function public.grupo_auxiliares_check_max_liderazgo();

-- =========================================================================
-- Familias
-- =========================================================================
create table public.familias (
  id uuid primary key default gen_random_uuid(),
  iglesia_id uuid not null references public.iglesias (id),
  nombre text not null,
  padre_miembro_id uuid references public.miembros (id),
  madre_miembro_id uuid references public.miembros (id),
  creado_en timestamptz not null default now()
);
create index familias_iglesia_id_idx on public.familias (iglesia_id);

create table public.familia_hijos (
  familia_id uuid not null references public.familias (id) on delete cascade,
  miembro_id uuid not null references public.miembros (id),
  primary key (familia_id, miembro_id)
);

-- =========================================================================
-- Comisiones de miembros (M:N)
-- =========================================================================
create table public.miembro_comisiones (
  miembro_id uuid not null references public.miembros (id) on delete cascade,
  comision_id uuid not null references public.comisiones (id),
  primary key (miembro_id, comision_id)
);

-- =========================================================================
-- Helpers para RLS
-- =========================================================================
create or replace function public.miembro_actual()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.id
  from public.miembros m
  join public.usuarios u on u.persona_id = m.persona_id
  where u.id = auth.uid()
  limit 1;
$$;

create or replace function public.es_encargado_de_grupo(p_grupo_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1 from public.grupos
    where id = p_grupo_id and encargado_miembro_id = public.miembro_actual()
  ) or exists(
    select 1 from public.grupo_auxiliares
    where grupo_id = p_grupo_id and miembro_id = public.miembro_actual()
  );
$$;

-- =========================================================================
-- Alta atómica de persona + miembro (mismo patrón que crear_ministro:
-- security definer con verificación explícita de permisos, para evitar el
-- problema de RETURNING contra una fila que aún no cumple personas_select).
-- =========================================================================
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
  p_ministro_bautizo_id uuid default null,
  p_fecha_espiritu_santo date default null,
  p_ministro_testifico_id uuid default null,
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
    ministro_bautizo_id, fecha_espiritu_santo, ministro_testifico_id,
    nivel_estudios_id, profesion_ocupacion_id, estado_civil_id,
    credencial_vigente_hasta
  )
  values (
    v_persona_id, p_iglesia_id, p_grupo_id, p_correo_personal,
    p_lugar_nacimiento_ciudad_id, p_fecha_bautismo, p_lugar_bautismo,
    p_ministro_bautizo_id, p_fecha_espiritu_santo, p_ministro_testifico_id,
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

-- =========================================================================
-- RLS
-- =========================================================================
alter table public.miembros enable row level security;
alter table public.grupos enable row level security;
alter table public.grupo_auxiliares enable row level security;
alter table public.familias enable row level security;
alter table public.familia_hijos enable row level security;
alter table public.miembro_comisiones enable row level security;

-- miembros: sin política de INSERT (solo vía crear_miembro, security
-- definer). Select/update/delete sí están disponibles directamente.
create policy miembros_select on public.miembros
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
    or (
      public.rol_actual() in ('encargado_grupo', 'auxiliar_grupo')
      and public.es_encargado_de_grupo(grupo_id)
    )
    or persona_id = (select persona_id from public.usuarios where id = auth.uid())
  );

create policy miembros_update_admin_o_encargado on public.miembros
  for update to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  );

create policy miembros_delete_admin_o_encargado on public.miembros
  for delete to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  );

-- grupos: alta/edición de grupos y asignación de encargado es tarea de
-- ministro_en_turno/encargado_estadistica (regla de negocio 10), no de los
-- propios encargados de grupo.
create policy grupos_select on public.grupos
  for select to authenticated using (true);

create policy grupos_write_admin_o_encargado on public.grupos
  for all to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  )
  with check (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  );

create policy grupo_auxiliares_select on public.grupo_auxiliares
  for select to authenticated using (true);

create policy grupo_auxiliares_write_admin_o_encargado on public.grupo_auxiliares
  for all to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and grupo_id in (select id from public.grupos where iglesia_id = public.iglesia_actual())
    )
  )
  with check (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and grupo_id in (select id from public.grupos where iglesia_id = public.iglesia_actual())
    )
  );

-- familias: mismo alcance que miembros/grupos (staff de la iglesia)
create policy familias_select on public.familias
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  );

create policy familias_write_admin_o_encargado on public.familias
  for all to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  )
  with check (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and iglesia_id = public.iglesia_actual()
    )
  );

create policy familia_hijos_select on public.familia_hijos
  for select to authenticated using (true);

create policy familia_hijos_write_admin_o_encargado on public.familia_hijos
  for all to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and familia_id in (select id from public.familias where iglesia_id = public.iglesia_actual())
    )
  )
  with check (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and familia_id in (select id from public.familias where iglesia_id = public.iglesia_actual())
    )
  );

-- miembro_comisiones: visibles junto con el miembro; escritura para staff
create policy miembro_comisiones_select on public.miembro_comisiones
  for select to authenticated using (true);

create policy miembro_comisiones_write_admin_o_encargado on public.miembro_comisiones
  for all to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
  )
  with check (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
  );
