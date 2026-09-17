-- Fase 5: reporte de fin de administración (regla de negocio 7)
-- Ver PLAN.md sección 5.8.

create table public.reportes_administracion (
  id uuid primary key default gen_random_uuid(),
  ministro_id uuid not null references public.ministros (id),
  fecha_generacion timestamptz not null default now(),
  total_activos int not null,
  total_retirados_temporales int not null,
  total_archivo int not null,
  detalle jsonb not null
);
create index reportes_administracion_ministro_id_idx on public.reportes_administracion (ministro_id);

alter table public.reportes_administracion enable row level security;

create policy reportes_administracion_select on public.reportes_administracion
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and ministro_id in (
        select id from public.ministros where iglesia_id = public.iglesia_actual()
      )
    )
  );

-- Snapshot de la iglesia del ministro al momento de generarse (no cambia
-- retroactivamente aunque las categorías de los miembros sigan
-- evolucionando después).
create or replace function public.generar_reporte_administracion(p_ministro_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_iglesia_id uuid;
  v_reporte_id uuid;
  v_detalle jsonb;
  v_total_activos int;
  v_total_retirados int;
  v_total_archivo int;
begin
  select iglesia_id into v_iglesia_id from public.ministros where id = p_ministro_id;

  if v_iglesia_id is null then
    raise exception 'Ministro no encontrado';
  end if;

  if not (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and v_iglesia_id = public.iglesia_actual()
    )
  ) then
    raise exception 'No tienes permiso para generar este reporte';
  end if;

  select
    count(*) filter (where m.categoria = 'activo'),
    count(*) filter (where m.categoria = 'retirado_temporal'),
    count(*) filter (where m.categoria = 'archivo'),
    jsonb_agg(jsonb_build_object(
      'miembro_id', m.id,
      'nombres', p.nombres,
      'apellido_paterno', p.apellido_paterno,
      'apellido_materno', p.apellido_materno,
      'categoria', m.categoria
    ))
  into v_total_activos, v_total_retirados, v_total_archivo, v_detalle
  from public.miembros m
  join public.personas p on p.id = m.persona_id
  where m.iglesia_id = v_iglesia_id;

  insert into public.reportes_administracion (
    ministro_id, total_activos, total_retirados_temporales, total_archivo, detalle
  )
  values (
    p_ministro_id, v_total_activos, v_total_retirados, v_total_archivo,
    coalesce(v_detalle, '[]'::jsonb)
  )
  returning id into v_reporte_id;

  return v_reporte_id;
end;
$$;

revoke execute on function public.generar_reporte_administracion from public;
grant execute on function public.generar_reporte_administracion to authenticated;
