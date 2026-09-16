-- Fase 1: estructura organizacional — iglesias, personas, ministros
-- Ver Documents/personal/iglesia-saas/PLAN.md secciones 5.1, 5.2

-- =========================================================================
-- usuarios: se agrega iglesia_id como ancla de alcance para roles de
-- iglesia (encargado_estadistica, ministro_en_turno) que no necesariamente
-- están ligados a una persona/ministro. Ver PLAN.md sección 9.
-- =========================================================================
alter table public.usuarios
  add column iglesia_id uuid;

-- =========================================================================
-- Personas (identidad base, compartida por ministros y —en Fase 2— miembros)
-- =========================================================================
create table public.personas (
  id uuid primary key default gen_random_uuid(),
  nombres text not null,
  apellido_paterno text not null,
  apellido_materno text,
  fecha_nacimiento date not null,
  sexo text not null check (sexo in ('M', 'F')),
  telefono_celular text,
  curp text,
  foto_perfil_url text,
  creado_en timestamptz not null default now()
);

alter table public.usuarios
  add constraint usuarios_persona_id_fkey
  foreign key (persona_id) references public.personas (id);

-- =========================================================================
-- Iglesias
-- ciudad_id/estado_id/pais_id se derivan de colonia_id (trigger abajo) para
-- evitar inconsistencias, aunque quedan como columnas propias para poder
-- filtrar directamente sin atravesar el join a colonias.
-- =========================================================================
create table public.iglesias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  calle_numero text not null,
  colonia_id uuid not null references public.colonias (id),
  codigo_postal text not null,
  google_maps_link text,
  telefono_casa_pastoral text,
  distrito_id uuid not null references public.distritos (id),
  ciudad_id uuid not null references public.ciudades (id),
  estado_id uuid not null references public.estados (id),
  pais_id uuid not null references public.paises (id),
  creado_en timestamptz not null default now()
);
create index iglesias_distrito_id_idx on public.iglesias (distrito_id);
create index iglesias_estado_id_idx on public.iglesias (estado_id);
create index iglesias_pais_id_idx on public.iglesias (pais_id);

create or replace function public.iglesias_derivar_geografia()
returns trigger
language plpgsql
as $$
begin
  select c.estado_id, e.pais_id
  into strict new.estado_id, new.pais_id
  from public.ciudades c
  join public.estados e on e.id = c.estado_id
  where c.id = new.ciudad_id;
  return new;
end;
$$;

create or replace function public.iglesias_sync_ciudad_desde_colonia()
returns trigger
language plpgsql
as $$
begin
  select ciudad_id into strict new.ciudad_id
  from public.colonias
  where id = new.colonia_id;
  return new;
end;
$$;

create trigger iglesias_sync_ciudad
  before insert or update of colonia_id on public.iglesias
  for each row execute function public.iglesias_sync_ciudad_desde_colonia();

create trigger iglesias_sync_geografia
  before insert or update of ciudad_id, colonia_id on public.iglesias
  for each row execute function public.iglesias_derivar_geografia();

alter table public.usuarios
  add constraint usuarios_iglesia_id_fkey
  foreign key (iglesia_id) references public.iglesias (id);

-- =========================================================================
-- Ministros
-- =========================================================================
create table public.ministros (
  id uuid primary key default gen_random_uuid(),
  persona_id uuid not null references public.personas (id),
  iglesia_id uuid not null references public.iglesias (id),
  correo_institucional text not null unique,
  fecha_inicio_administracion date not null,
  fecha_fin_administracion date,
  grado_id uuid not null references public.grados_ministros (id),
  es_pastor_distrital boolean not null default false,
  distrito_a_cargo_id uuid references public.distritos (id),
  es_pastor_jurisdiccional boolean not null default false,
  jurisdiccion_a_cargo_id uuid references public.jurisdicciones (id),
  creado_en timestamptz not null default now(),
  constraint ministros_distrital_check check (
    (es_pastor_distrital = false and distrito_a_cargo_id is null)
    or (es_pastor_distrital = true and distrito_a_cargo_id is not null)
  ),
  constraint ministros_jurisdiccional_check check (
    (es_pastor_jurisdiccional = false and jurisdiccion_a_cargo_id is null)
    or (es_pastor_jurisdiccional = true and jurisdiccion_a_cargo_id is not null)
  )
);
create index ministros_iglesia_id_idx on public.ministros (iglesia_id);
create index ministros_persona_id_idx on public.ministros (persona_id);

-- =========================================================================
-- Helper adicional: iglesia del usuario actual (propia o vía ministerio)
-- =========================================================================
create or replace function public.iglesia_actual()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select u.iglesia_id from public.usuarios u where u.id = auth.uid()),
    (select m.iglesia_id
       from public.usuarios u
       join public.ministros m on m.persona_id = u.persona_id
      where u.id = auth.uid()
      limit 1)
  );
$$;

-- =========================================================================
-- RLS
-- =========================================================================
alter table public.personas enable row level security;
alter table public.iglesias enable row level security;
alter table public.ministros enable row level security;

-- iglesias: lectura abierta a autenticados (se requiere poder filtrar/listar
-- iglesias por país/distrito/estado desde toda la organización); alta y baja
-- reservadas a super_admin; edición también permitida a ministro_en_turno /
-- encargado_estadistica de esa misma iglesia.
create policy iglesias_select_authenticated on public.iglesias
  for select to authenticated using (true);

create policy iglesias_insert_admin on public.iglesias
  for insert to authenticated
  with check (public.rol_actual() = 'super_admin');

create policy iglesias_delete_admin on public.iglesias
  for delete to authenticated
  using (public.rol_actual() = 'super_admin');

create policy iglesias_update_admin_o_encargado on public.iglesias
  for update to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and id = public.iglesia_actual()
    )
  );

-- ministros: lectura abierta a autenticados (directorio interno); escritura
-- para super_admin o para el personal de esa misma iglesia.
create policy ministros_select_authenticated on public.ministros
  for select to authenticated using (true);

create policy ministros_write_admin_o_encargado on public.ministros
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

-- personas: cada quien ve/edita la suya propia; el personal de una iglesia
-- puede ver/editar las personas que son ministros de su iglesia; super_admin
-- ve/edita todas.
create policy personas_select on public.personas
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or id = (select persona_id from public.usuarios where id = auth.uid())
    or id in (
      select persona_id from public.ministros where iglesia_id = public.iglesia_actual()
    )
  );

create policy personas_write on public.personas
  for all to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or id = (select persona_id from public.usuarios where id = auth.uid())
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and id in (
        select persona_id from public.ministros where iglesia_id = public.iglesia_actual()
      )
    )
  )
  with check (
    public.rol_actual() = 'super_admin'
    or id = (select persona_id from public.usuarios where id = auth.uid())
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and id in (
        select persona_id from public.ministros where iglesia_id = public.iglesia_actual()
      )
    )
  );
