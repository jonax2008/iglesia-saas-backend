-- Fase 0: catálogos base, roles y usuarios
-- Ver Documents/personal/iglesia-saas/PLAN.md secciones 5.1 y 5.4

create extension if not exists pgcrypto;

-- =========================================================================
-- Roles (catálogo fijo de 6 roles, ver PLAN.md 5.4)
-- =========================================================================
create table public.roles (
  id smallint primary key,
  nombre text not null unique
);

insert into public.roles (id, nombre) values
  (1, 'super_admin'),
  (2, 'encargado_estadistica'),
  (3, 'ministro_en_turno'),
  (4, 'encargado_grupo'),
  (5, 'auxiliar_grupo'),
  (6, 'miembro');

-- =========================================================================
-- Usuarios (perfil de aplicación 1:1 con auth.users)
-- persona_id se agrega con FK en la migración de Fase 1/2 (tabla personas aún no existe)
-- =========================================================================
create table public.usuarios (
  id uuid primary key references auth.users (id) on delete cascade,
  correo text not null unique,
  estatus text not null default 'activo' check (estatus in ('activo', 'inactivo')),
  rol_id smallint not null references public.roles (id),
  persona_id uuid,
  creado_en timestamptz not null default now()
);

-- =========================================================================
-- Catálogos geográficos
-- =========================================================================
create table public.paises (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);

create table public.estados (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  pais_id uuid not null references public.paises (id),
  unique (pais_id, nombre)
);

create table public.ciudades (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  estado_id uuid not null references public.estados (id),
  unique (estado_id, nombre)
);

-- Catálogo normalizado de colonias (seed futuro desde SEPOMEX, ver PLAN.md 9)
create table public.colonias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  codigo_postal text not null,
  ciudad_id uuid not null references public.ciudades (id)
);
create index colonias_codigo_postal_idx on public.colonias (codigo_postal);
create index colonias_ciudad_id_idx on public.colonias (ciudad_id);

-- =========================================================================
-- Catálogos organizacionales
-- =========================================================================
create table public.jurisdicciones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);

-- Un distrito es independiente de la geografía (puede agrupar iglesias de
-- distintos estados) y se reorganiza cuando cambian los pastores distritales.
create table public.distritos (
  id uuid primary key default gen_random_uuid(),
  numero integer not null unique,
  nombre text not null,
  jurisdiccion_id uuid not null references public.jurisdicciones (id)
);

-- =========================================================================
-- Catálogos de personas (ministros y miembros)
-- =========================================================================
create table public.grados_ministros (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);
insert into public.grados_ministros (nombre) values
  ('Obrero'), ('Encargado'), ('Diácono'), ('Pastor');

create table public.comisiones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);

create table public.niveles_estudio (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);

create table public.estados_civiles (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);

create table public.profesiones_ocupaciones (
  id uuid primary key default gen_random_uuid(),
  nombre text not null unique
);

-- Seed inicial: MVP en México (ver PLAN.md 9)
insert into public.paises (nombre) values ('México');

-- =========================================================================
-- Helper para RLS: rol del usuario autenticado actual
-- =========================================================================
create or replace function public.rol_actual()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.nombre
  from public.usuarios u
  join public.roles r on r.id = u.rol_id
  where u.id = auth.uid();
$$;

-- =========================================================================
-- RLS
-- =========================================================================
alter table public.roles enable row level security;
alter table public.usuarios enable row level security;
alter table public.paises enable row level security;
alter table public.estados enable row level security;
alter table public.ciudades enable row level security;
alter table public.colonias enable row level security;
alter table public.jurisdicciones enable row level security;
alter table public.distritos enable row level security;
alter table public.grados_ministros enable row level security;
alter table public.comisiones enable row level security;
alter table public.niveles_estudio enable row level security;
alter table public.estados_civiles enable row level security;
alter table public.profesiones_ocupaciones enable row level security;

-- roles: catálogo de solo lectura para cualquier usuario autenticado
create policy roles_select_authenticated on public.roles
  for select to authenticated using (true);

-- usuarios: cada quien ve/edita su propia fila; super_admin ve/edita todas
create policy usuarios_select_propio_o_admin on public.usuarios
  for select to authenticated
  using (id = auth.uid() or public.rol_actual() = 'super_admin');

create policy usuarios_update_propio_o_admin on public.usuarios
  for update to authenticated
  using (id = auth.uid() or public.rol_actual() = 'super_admin');

create policy usuarios_insert_admin on public.usuarios
  for insert to authenticated
  with check (public.rol_actual() = 'super_admin');

-- Catálogos: lectura abierta a autenticados, escritura solo super_admin en Fase 0
-- (en fases posteriores se podría delegar a encargado_estadistica/ministro_en_turno
-- según el catálogo, ver PLAN.md 9)
do $$
declare
  t text;
begin
  foreach t in array array[
    'paises', 'estados', 'ciudades', 'colonias', 'jurisdicciones', 'distritos',
    'grados_ministros', 'comisiones', 'niveles_estudio', 'estados_civiles',
    'profesiones_ocupaciones'
  ]
  loop
    execute format(
      'create policy %I_select_authenticated on public.%I for select to authenticated using (true);',
      t, t
    );
    execute format(
      'create policy %I_write_admin on public.%I for all to authenticated using (public.rol_actual() = %L) with check (public.rol_actual() = %L);',
      t, t, 'super_admin', 'super_admin'
    );
  end loop;
end $$;
