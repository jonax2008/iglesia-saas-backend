# iglesia-saas-backend

Backend en Supabase (Postgres + Auth + RLS + Edge Functions) para el SaaS de control estadístico de Iglesia.

Plan completo y decisiones de diseño: ver `PLAN.md` en el repo hermano `iglesia-saas` (`Documents/personal/iglesia-saas/PLAN.md`).

## Desarrollo local

Requiere [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) y Docker.

```bash
supabase start   # levanta Postgres, Auth, Storage, Studio, etc. localmente
supabase stop     # detiene el stack local
```

Studio local: http://127.0.0.1:54323

## Migraciones

Las migraciones viven en `supabase/migrations/` y se aplican automáticamente al hacer `supabase start` o `supabase db reset`.

- `20260916000000_catalogos_roles_usuarios.sql` — catálogos base (geográficos, organizacionales, de personas), roles fijos y tabla `usuarios`, con RLS.

## Despliegue

```bash
supabase link --project-ref <project-ref>
supabase db push
```
