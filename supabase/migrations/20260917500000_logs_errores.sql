-- Log de errores de aplicación (para poder diagnosticar fallos como el
-- de "no aparecen los ministros" sin depender solo de los logs de Vercel).
create table public.logs_errores (
  id uuid primary key default gen_random_uuid(),
  creado_en timestamptz not null default now(),
  ruta text not null,
  operacion text not null,
  mensaje text not null,
  codigo text,
  detalles text,
  hint text,
  usuario_id uuid references public.usuarios (id),
  contexto jsonb
);
create index logs_errores_creado_en_idx on public.logs_errores (creado_en desc);

alter table public.logs_errores enable row level security;

-- cualquier usuario autenticado puede registrar un error (propio o de la
-- app), pero solo super_admin puede leer el log completo.
create policy logs_errores_insert on public.logs_errores
  for insert to authenticated
  with check (true);

create policy logs_errores_select on public.logs_errores
  for select to authenticated
  using (public.rol_actual() = 'super_admin');
