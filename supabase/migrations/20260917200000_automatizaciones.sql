-- Fase 4: automatizaciones
-- Ver Documents/personal/iglesia-saas/PLAN.md sección 6 y reglas de
-- negocio 3 y 5.

-- =========================================================================
-- Notificaciones (canal in-app únicamente, ver PLAN.md 5.6)
-- =========================================================================
create table public.notificaciones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null references public.usuarios (id),
  tipo text not null check (tipo in ('cambio_grupo_por_edad', 'otro')),
  mensaje text not null,
  entidad_tipo text,
  entidad_id uuid,
  leida boolean not null default false,
  creado_en timestamptz not null default now()
);
create index notificaciones_usuario_id_idx on public.notificaciones (usuario_id, leida);

alter table public.notificaciones enable row level security;

create policy notificaciones_select on public.notificaciones
  for select to authenticated
  using (usuario_id = auth.uid());

create policy notificaciones_update on public.notificaciones
  for update to authenticated
  using (usuario_id = auth.uid())
  with check (usuario_id = auth.uid());

-- =========================================================================
-- Bitácoras de Fase 4 (append-only: sin política de update/delete, solo
-- se escriben desde las funciones security definer de abajo)
-- =========================================================================
create table public.bitacora_categoria_miembro (
  id uuid primary key default gen_random_uuid(),
  miembro_id uuid not null references public.miembros (id),
  categoria_anterior text not null,
  categoria_nueva text not null,
  motivo text not null
    check (motivo in ('automatico_faltas', 'automatico_reactivacion', 'manual')),
  usuario_id uuid references public.usuarios (id),
  observaciones text,
  creado_en timestamptz not null default now()
);

create table public.bitacora_movimientos_grupo (
  id uuid primary key default gen_random_uuid(),
  miembro_id uuid not null references public.miembros (id),
  grupo_origen_id uuid references public.grupos (id),
  grupo_destino_id uuid not null references public.grupos (id),
  usuario_id uuid not null references public.usuarios (id),
  respeta_criterio_edad boolean not null,
  observaciones text not null,
  creado_en timestamptz not null default now()
);

alter table public.bitacora_categoria_miembro enable row level security;
alter table public.bitacora_movimientos_grupo enable row level security;

create policy bitacora_categoria_miembro_select on public.bitacora_categoria_miembro
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
  );

create policy bitacora_movimientos_grupo_select on public.bitacora_movimientos_grupo
  for select to authenticated
  using (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and miembro_id in (select id from public.miembros where iglesia_id = public.iglesia_actual())
    )
  );

-- =========================================================================
-- Transición/reactivación automática de categoría (regla de negocio 5).
-- "Día completo": un día cuenta como asistido si hay >=1 registro
-- 'asistencia'; cuenta como falta completa si todos sus registros ese día
-- son 'falta'. Referencia de ausencia = última asistencia positiva (o la
-- fecha de alta si nunca ha asistido).
--   activo/retirado_temporal -> archivo: referencia >= 1 año de antigüedad
--   activo -> retirado_temporal: referencia >= 3 meses de antigüedad
--   retirado_temporal/archivo -> activo: ha asistido en los últimos 3
--     meses y no tiene una falta completa en esos mismos 3 meses
-- Puede llamarse sin argumentos (todas las iglesias, requiere
-- super_admin o ejecución vía cron sin JWT) o acotado a una iglesia
-- (ministro_en_turno/encargado_estadistica de esa iglesia).
-- =========================================================================
create or replace function public.actualizar_categorias_miembros(p_iglesia_id uuid default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actualizados integer := 0;
  r record;
begin
  if auth.uid() is not null then
    if p_iglesia_id is null and public.rol_actual() <> 'super_admin' then
      raise exception 'Solo super_admin puede actualizar categorías de todas las iglesias';
    end if;
    if p_iglesia_id is not null and not (
      public.rol_actual() = 'super_admin'
      or (
        public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
        and p_iglesia_id = public.iglesia_actual()
      )
    ) then
      raise exception 'No tienes permiso para actualizar categorías de esta iglesia';
    end if;
  end if;

  for r in (
    select
      m.id as miembro_id,
      m.categoria,
      coalesce(ma.ultima_asistencia, m.creado_en::date) as referencia_ausencia,
      ma.ultima_asistencia,
      mf.ultima_falta_completa
    from public.miembros m
    left join lateral (
      select max(fecha) as ultima_asistencia
      from public.asistencias a
      where a.miembro_id = m.id and a.valor = 'asistencia'
    ) ma on true
    left join lateral (
      select max(d.fecha) as ultima_falta_completa
      from (
        select fecha, bool_or(valor = 'asistencia') as asistio
        from public.asistencias a2
        where a2.miembro_id = m.id
        group by fecha
      ) d
      where not d.asistio
    ) mf on true
    where m.categoria in ('activo', 'retirado_temporal', 'archivo')
      and (p_iglesia_id is null or m.iglesia_id = p_iglesia_id)
  )
  loop
    if r.categoria in ('activo', 'retirado_temporal')
       and r.referencia_ausencia <= (current_date - interval '1 year') then
      update public.miembros set categoria = 'archivo' where id = r.miembro_id;
      insert into public.bitacora_categoria_miembro (miembro_id, categoria_anterior, categoria_nueva, motivo)
      values (r.miembro_id, r.categoria, 'archivo', 'automatico_faltas');
      v_actualizados := v_actualizados + 1;
    elsif r.categoria = 'activo'
          and r.referencia_ausencia <= (current_date - interval '3 months') then
      update public.miembros set categoria = 'retirado_temporal' where id = r.miembro_id;
      insert into public.bitacora_categoria_miembro (miembro_id, categoria_anterior, categoria_nueva, motivo)
      values (r.miembro_id, r.categoria, 'retirado_temporal', 'automatico_faltas');
      v_actualizados := v_actualizados + 1;
    elsif r.categoria in ('retirado_temporal', 'archivo')
          and r.ultima_asistencia is not null
          and r.ultima_asistencia >= (current_date - interval '3 months')
          and (r.ultima_falta_completa is null or r.ultima_falta_completa <= (current_date - interval '3 months')) then
      update public.miembros set categoria = 'activo' where id = r.miembro_id;
      insert into public.bitacora_categoria_miembro (miembro_id, categoria_anterior, categoria_nueva, motivo)
      values (r.miembro_id, r.categoria, 'activo', 'automatico_reactivacion');
      v_actualizados := v_actualizados + 1;
    end if;
  end loop;

  return v_actualizados;
end;
$$;

revoke execute on function public.actualizar_categorias_miembros from public;
grant execute on function public.actualizar_categorias_miembros to authenticated;

-- =========================================================================
-- Aviso 1 mes antes de cambio de grupo por edad (regla de negocio 3).
-- =========================================================================
create or replace function public.generar_avisos_cambio_grupo()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_generados integer := 0;
  r record;
  v_usuario_id uuid;
  v_mensaje text;
begin
  if auth.uid() is not null
     and public.rol_actual() not in ('super_admin', 'ministro_en_turno', 'encargado_estadistica') then
    raise exception 'No tienes permiso para generar avisos';
  end if;

  for r in (
    select
      m.id as miembro_id,
      m.grupo_id,
      m.iglesia_id,
      p.nombres,
      p.apellido_paterno,
      g.nombre as grupo_nombre,
      g.edad_final,
      g.encargado_miembro_id,
      (p.fecha_nacimiento + ((g.edad_final + 1) || ' years')::interval)::date as fecha_limite
    from public.miembros m
    join public.personas p on p.id = m.persona_id
    join public.grupos g on g.id = m.grupo_id
    where m.categoria = 'activo'
  )
  loop
    if r.fecha_limite between current_date and current_date + interval '30 days' then
      if exists (
        select 1 from public.notificaciones
        where tipo = 'cambio_grupo_por_edad'
          and entidad_id = r.miembro_id
          and creado_en > now() - interval '35 days'
      ) then
        continue;
      end if;

      v_mensaje := format(
        '%s %s cumplirá %s años el %s y saldrá del rango de edad del grupo "%s".',
        r.nombres, r.apellido_paterno, r.edad_final + 1,
        to_char(r.fecha_limite, 'DD/MM/YYYY'), r.grupo_nombre
      );

      for v_usuario_id in (
        select u.id from public.usuarios u
        join public.miembros me on me.persona_id = u.persona_id
        where me.id = r.encargado_miembro_id
        union
        select u.id from public.usuarios u
        join public.miembros me on me.persona_id = u.persona_id
        join public.grupo_auxiliares ga on ga.miembro_id = me.id
        where ga.grupo_id = r.grupo_id
        union
        select u.id from public.usuarios u
        join public.roles ro on ro.id = u.rol_id
        where u.iglesia_id = r.iglesia_id and ro.nombre in ('ministro_en_turno', 'encargado_estadistica')
      )
      loop
        insert into public.notificaciones (usuario_id, tipo, mensaje, entidad_tipo, entidad_id)
        values (v_usuario_id, 'cambio_grupo_por_edad', v_mensaje, 'miembro', r.miembro_id);
      end loop;

      v_generados := v_generados + 1;
    end if;
  end loop;

  return v_generados;
end;
$$;

revoke execute on function public.generar_avisos_cambio_grupo from public;
grant execute on function public.generar_avisos_cambio_grupo to authenticated;

-- =========================================================================
-- Movimiento manual de miembro entre grupos (regla de negocio 3): solo
-- ministro_en_turno/encargado_estadistica, exige observaciones, registra
-- si el criterio de edad se respetó o no (sin bloquear el movimiento).
-- =========================================================================
create or replace function public.mover_miembro_grupo(
  p_miembro_id uuid,
  p_grupo_destino_id uuid,
  p_observaciones text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_iglesia_id uuid;
  v_grupo_origen_id uuid;
  v_edad int;
  v_edad_inicial int;
  v_edad_final int;
  v_respeta_edad boolean;
begin
  select iglesia_id, grupo_id into v_iglesia_id, v_grupo_origen_id
  from public.miembros where id = p_miembro_id;

  if v_iglesia_id is null then
    raise exception 'Miembro no encontrado';
  end if;

  if not (
    public.rol_actual() = 'super_admin'
    or (
      public.rol_actual() in ('ministro_en_turno', 'encargado_estadistica')
      and v_iglesia_id = public.iglesia_actual()
    )
  ) then
    raise exception 'Solo el ministro en turno o el encargado de estadística pueden mover miembros entre grupos';
  end if;

  if p_observaciones is null or trim(p_observaciones) = '' then
    raise exception 'Debes justificar el movimiento con observaciones';
  end if;

  select extract(year from age(p.fecha_nacimiento))::int into v_edad
  from public.personas p join public.miembros m on m.persona_id = p.id
  where m.id = p_miembro_id;

  select edad_inicial, edad_final into v_edad_inicial, v_edad_final
  from public.grupos where id = p_grupo_destino_id;

  v_respeta_edad := v_edad between v_edad_inicial and v_edad_final;

  update public.miembros set grupo_id = p_grupo_destino_id where id = p_miembro_id;

  insert into public.bitacora_movimientos_grupo (
    miembro_id, grupo_origen_id, grupo_destino_id, usuario_id, respeta_criterio_edad, observaciones
  )
  values (p_miembro_id, v_grupo_origen_id, p_grupo_destino_id, auth.uid(), v_respeta_edad, p_observaciones);

  return v_respeta_edad;
end;
$$;

revoke execute on function public.mover_miembro_grupo from public;
grant execute on function public.mover_miembro_grupo to authenticated;
