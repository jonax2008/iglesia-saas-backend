-- Fase 3: asistencia
-- Ver Documents/personal/iglesia-saas/PLAN.md sección 5.5 y reglas de
-- negocio 4 y 8.

create table public.asistencias (
  id uuid primary key default gen_random_uuid(),
  miembro_id uuid not null references public.miembros (id),
  fecha date not null,
  categoria text not null
    check (categoria in ('oracion_5am', 'oracion_9am', 'oracion_7pm', 'dominical', 'servicio')),
  valor text not null check (valor in ('asistencia', 'falta')),
  creado_por uuid references public.usuarios (id),
  creado_en timestamptz not null default now(),
  unique (miembro_id, fecha, categoria)
);
create index asistencias_miembro_fecha_idx on public.asistencias (miembro_id, fecha);
create index asistencias_fecha_idx on public.asistencias (fecha);

create table public.bitacora_asistencia (
  id uuid primary key default gen_random_uuid(),
  asistencia_id uuid not null references public.asistencias (id),
  valor_anterior text not null,
  valor_nuevo text not null,
  usuario_id uuid not null references public.usuarios (id),
  observaciones text not null,
  creado_en timestamptz not null default now()
);
create index bitacora_asistencia_asistencia_id_idx on public.bitacora_asistencia (asistencia_id);

-- =========================================================================
-- Corrección de asistencia: única vía de cambio de valor (no hay política
-- de UPDATE directa sobre asistencias). Aplica la regla de negocio 4:
-- ventana de corrección = mes de la fecha + el mes siguiente + 3 días, y
-- exige observaciones, registrando todo en bitacora_asistencia.
-- =========================================================================
create or replace function public.corregir_asistencia(
  p_asistencia_id uuid,
  p_valor_nuevo text,
  p_observaciones text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_miembro_id uuid;
  v_valor_anterior text;
  v_fecha date;
  v_autorizado boolean;
begin
  select miembro_id, valor, fecha
  into v_miembro_id, v_valor_anterior, v_fecha
  from public.asistencias
  where id = p_asistencia_id;

  if v_miembro_id is null then
    raise exception 'Asistencia no encontrada';
  end if;

  select (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and v_miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
    or (
      public.rol_actual() in ('encargado_grupo', 'auxiliar_grupo')
      and v_miembro_id in (
        select id from public.miembros m where public.es_encargado_de_grupo(m.grupo_id)
      )
    )
  ) into v_autorizado;

  if not v_autorizado then
    raise exception 'No tienes permiso para corregir esta asistencia';
  end if;

  if p_observaciones is null or trim(p_observaciones) = '' then
    raise exception 'Debes justificar la corrección con observaciones';
  end if;

  if p_valor_nuevo not in ('asistencia', 'falta') then
    raise exception 'Valor de asistencia inválido';
  end if;

  if now() >= date_trunc('month', v_fecha) + interval '2 months' + interval '3 days' then
    raise exception 'Ya pasó la ventana de corrección (mes en curso + 3 días del mes siguiente)';
  end if;

  if p_valor_nuevo = v_valor_anterior then
    return;
  end if;

  update public.asistencias set valor = p_valor_nuevo where id = p_asistencia_id;

  insert into public.bitacora_asistencia (
    asistencia_id, valor_anterior, valor_nuevo, usuario_id, observaciones
  )
  values (p_asistencia_id, v_valor_anterior, p_valor_nuevo, auth.uid(), p_observaciones);
end;
$$;

revoke execute on function public.corregir_asistencia from public;
grant execute on function public.corregir_asistencia to authenticated;

-- =========================================================================
-- RLS
-- =========================================================================
alter table public.asistencias enable row level security;
alter table public.bitacora_asistencia enable row level security;

-- Sin política de update/delete: el único cambio de valor permitido es vía
-- corregir_asistencia (security definer), que deja rastro en la bitácora.
create policy asistencias_select on public.asistencias
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
    or (
      public.rol_actual() in ('encargado_grupo', 'auxiliar_grupo')
      and miembro_id in (
        select id from public.miembros m where public.es_encargado_de_grupo(m.grupo_id)
      )
    )
    or miembro_id = public.miembro_actual()
  );

create policy asistencias_insert on public.asistencias
  for insert to authenticated
  with check (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
    or (
      public.rol_actual() in ('encargado_grupo', 'auxiliar_grupo')
      and miembro_id in (
        select id from public.miembros m where public.es_encargado_de_grupo(m.grupo_id)
      )
    )
  );

create policy bitacora_asistencia_select on public.bitacora_asistencia
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and asistencia_id in (
        select a.id from public.asistencias a
        join public.miembros m on m.id = a.miembro_id
        where m.iglesia_id = public.iglesia_actual()
      )
    )
    or (
      public.rol_actual() in ('encargado_grupo', 'auxiliar_grupo')
      and asistencia_id in (
        select a.id from public.asistencias a
        join public.miembros m on m.id = a.miembro_id
        where public.es_encargado_de_grupo(m.grupo_id)
      )
    )
  );
